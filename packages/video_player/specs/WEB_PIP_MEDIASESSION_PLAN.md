# Web: Picture-in-Picture & MediaSession Implementation Plan (IMPLEMENTED)

## Current State

| Feature | Android | iOS | Web |
|---------|---------|-----|-----|
| PiP (enter/exit) | Activity-level PiP (Android 8+) | Video PiP via AVPictureInPictureController (iOS 15+) | **NOT IMPLEMENTED** |
| Auto-PiP | `setAutoEnterEnabled` (Android 12+) / `onUserLeaveHint` | `canStartPictureInPictureAutomaticallyFromInline` (iOS 14.2+) | **NOT IMPLEMENTED** |
| PiP state events | `pipStateChanged` via `PipCallbackHelper` | Delegate callbacks on `AVPictureInPictureControllerDelegate` | **NOT IMPLEMENTED** |
| MediaSession / Now Playing | Media3 `MediaSession` + foreground service notification | `MPRemoteCommandCenter` + `MPNowPlayingInfoCenter` | **NOT IMPLEMENTED** |
| Background playback | Foreground service via `PlaybackService` | `AVAudioSessionCategoryPlayback` + background task | **NOT IMPLEMENTED** (browsers handle natively) |

### Files to modify

- `video_player_web/lib/src/pkg_web_tweaks.dart` — add JS interop extensions for PiP + MediaSession APIs
- `video_player_web/lib/src/video_player.dart` — add PiP methods + MediaSession setup + event listeners
- `video_player_web/lib/video_player_web.dart` — implement platform interface methods (override `isPipSupported`, `enterPip`, `exitPip`, `isPipActive`, `setAutoEnterPip`, `enableBackgroundPlayback`, `disableBackgroundPlayback`)
- `video_player_web/example/integration_test/` — add integration tests

---

## Part 1: Picture-in-Picture

### 1A. Which PiP API to use?

There are **two** browser PiP APIs:

| | Standard Video PiP | Document PiP |
|--|---------------------|--------------|
| **API** | `video.requestPictureInPicture()` | `documentPictureInPicture.requestWindow()` |
| **Content** | `<video>` element only | Arbitrary HTML |
| **Controls** | Browser-provided overlay (auto-populated from MediaSession actions) | Full custom HTML/CSS |
| **Browser support** | ~94% (Chrome 70+, Safari 13.1+, Edge 79+, Firefox 68+ partial) | Chrome/Edge 116+ only, no Safari/Firefox |
| **Exit** | `document.exitPictureInPicture()` | `pipWindow.close()` |

**Recommendation: Use the Standard Video PiP API** (`requestPictureInPicture()`).

Reasons:
- Matches the iOS model (video-level PiP, not activity-level).
- ~94% browser support vs. ~27% for Document PiP.
- The browser automatically adds play/pause/seek controls based on MediaSession action handlers — no custom UI needed.
- Simpler implementation that aligns with the existing platform interface methods.
- Document PiP is better suited for video conferencing / custom UI scenarios which is not our use case.

### 1B. JS Interop Extensions (`pkg_web_tweaks.dart`)

Add the following extensions for APIs not yet in `package:web`:

```dart
// On HTMLVideoElement
external JSPromise<PictureInPictureWindow> requestPictureInPicture();

// On Document
external JSPromise<void> exitPictureInPicture();
external web.Element? get pictureInPictureElement;
external bool get pictureInPictureEnabled;

// PictureInPictureWindow interface
extension type PictureInPictureWindow._(JSObject _) implements JSObject {
  external int get width;
  external int get height;
}
```

**Note:** Before adding interop, check if `package:web >=0.5.1 <2.0.0` (current dep) already exposes these. If it does, use them directly. If not, add `@JS()` external bindings.

### 1C. VideoPlayer class changes (`video_player.dart`)

Add to the `VideoPlayer` class:

```dart
bool _isPipActive = false;

/// Whether PiP is supported by the browser.
bool get isPipSupported {
  // Check both: the document-level flag AND that the video element
  // actually has the method (Firefox has a non-standard implementation).
  return web.document.pictureInPictureEnabled == true;
}

/// Enter PiP mode.
Future<void> enterPip() async {
  await _videoElement.requestPictureInPicture();
  // Events will fire and update state via listeners
}

/// Exit PiP mode.
Future<void> exitPip() async {
  if (web.document.pictureInPictureElement != null) {
    await web.document.exitPictureInPicture();
  }
}

/// Whether PiP is currently active for this video.
bool get isPipActive => _isPipActive;
```

**Event listeners** (added in `initialize()`):

```dart
_videoElement.addEventListener('enterpictureinpicture', (web.Event event) {
  _isPipActive = true;
  final pipWindow = (event as dynamic).pictureInPictureWindow;
  _eventController.add(VideoEvent(
    eventType: VideoEventType.pipStateChanged,
    isPipActive: true,
    pipWindowSize: Size(pipWindow.width.toDouble(), pipWindow.height.toDouble()),
  ));
}.toJS);

_videoElement.addEventListener('leavepictureinpicture', (web.Event event) {
  _isPipActive = false;
  _eventController.add(VideoEvent(
    eventType: VideoEventType.pipStateChanged,
    isPipActive: false,
    // wasDismissed: not reliably detectable on web — the browser doesn't
    // distinguish between "user clicked X" vs "user clicked back to tab".
    // Always null/false on web.
  ));
}.toJS);
```

### 1D. VideoPlayerPlugin overrides (`video_player_web.dart`)

```dart
@override
Future<bool> isPipSupported() async {
  return _videoPlayers.values.firstOrNull?.isPipSupported ?? false;
  // Alternatively, check document.pictureInPictureEnabled directly.
}

@override
Future<void> enterPip(int playerId) async {
  return _player(playerId).enterPip();
}

@override
Future<void> exitPip(int playerId) async {
  return _player(playerId).exitPip();
}

@override
Future<bool> isPipActive(int playerId) async {
  return _player(playerId).isPipActive;
}
```

### 1E. Compatibility checks

The web implementation must handle:

1. **Feature detection** — `document.pictureInPictureEnabled` may be `undefined` in older browsers. The JS interop must handle this gracefully (e.g., return `false` when `undefined`).
2. **`disablePictureInPicture` attribute** — If `VideoPlayerWebOptions.controls.allowPictureInPicture` is `false`, `requestPictureInPicture()` will throw `InvalidStateError`. Guard `enterPip()` against this.
3. **Permissions Policy** — `requestPictureInPicture()` throws `SecurityError` if PiP is blocked by the page's Permissions Policy. Catch and surface as a `PlatformException`.
4. **User gesture requirement** — `requestPictureInPicture()` requires transient user activation. If called without a gesture, it throws `NotAllowedError`. Document this limitation. Auto-PiP (Part 3) is the workaround.
5. **No video track** — Throws `InvalidStateError` if the video has no video track (audio-only). Guard against this.
6. **Firefox** — Firefox uses its own non-standard PiP implementation. `document.pictureInPictureEnabled` may be `undefined`. `isPipSupported()` should return `false` for Firefox, or we detect Firefox-specific API separately. **Recommendation:** Only support the W3C standard API; Firefox PiP is browser-controlled and not programmable.

Error handling in `enterPip()`:

```dart
Future<void> enterPip() async {
  try {
    await _videoElement.requestPictureInPicture().toDart;
  } catch (e) {
    if (e is web.DOMException) {
      throw PlatformException(
        code: e.name,   // 'NotAllowedError', 'InvalidStateError', 'SecurityError'
        message: e.message,
      );
    }
    rethrow;
  }
}
```

---

## Part 2: MediaSession

### 2A. Overview

The Web MediaSession API (`navigator.mediaSession`) is the web equivalent of:
- Android: `Media3 MediaSession` + notification controls
- iOS: `MPRemoteCommandCenter` + `MPNowPlayingInfoCenter`

Browser support: ~96.7% (Chrome 73+, Edge 79+, Safari 15+, Firefox 82+).

On the web, MediaSession provides:
- **Metadata** — title, artist, album, artwork displayed in OS media controls (lock screen on mobile, media overlay on desktop)
- **Action handlers** — play, pause, seekto, seekbackward, seekforward, previoustrack, nexttrack
- **Playback state** — `playing`, `paused`, `none`
- **Position state** — duration, playback rate, current position

### 2B. Mapping to platform interface

The existing platform interface uses `enableBackgroundPlayback(playerId, {MediaInfo? mediaInfo})` and `disableBackgroundPlayback(playerId)`. On the web, "background playback" doesn't require a service — browsers handle audio playback in background tabs natively. However, **MediaSession metadata and controls** are what give the user control over that background playback.

So the mapping is:
- `enableBackgroundPlayback(mediaInfo)` → Set up `navigator.mediaSession` with metadata + action handlers
- `disableBackgroundPlayback()` → Clear metadata and remove action handlers

### 2C. JS Interop Extensions (`pkg_web_tweaks.dart`)

Check if `package:web` already exposes `navigator.mediaSession`. If not, add:

```dart
// navigator.mediaSession
extension MediaSessionAccess on web.Navigator {
  external web.MediaSession? get mediaSession;
}

// MediaSession interface
extension type MediaSession._(JSObject _) implements JSObject {
  external set metadata(MediaMetadata? metadata);
  external MediaMetadata? get metadata;
  external set playbackState(String state); // 'none', 'paused', 'playing'
  external String get playbackState;
  external void setActionHandler(String action, JSFunction? handler);
  external void setPositionState(JSObject? state);
}

// MediaMetadata interface
extension type MediaMetadata._(JSObject _) implements JSObject {
  external factory MediaMetadata(JSObject init);
}
```

### 2D. VideoPlayer class changes (`video_player.dart`)

Add a `MediaSessionManager` (or inline in `VideoPlayer`):

```dart
bool _mediaSessionEnabled = false;
MediaInfo? _currentMediaInfo;

void enableMediaSession(MediaInfo? mediaInfo) {
  _mediaSessionEnabled = true;
  _currentMediaInfo = mediaInfo;
  _setupMediaSession(mediaInfo);
}

void disableMediaSession() {
  _mediaSessionEnabled = false;
  _currentMediaInfo = null;
  _teardownMediaSession();
}

void _setupMediaSession(MediaInfo? mediaInfo) {
  final mediaSession = web.window.navigator.mediaSession;
  if (mediaSession == null) return; // Browser doesn't support MediaSession

  // 1. Set metadata
  if (mediaInfo != null) {
    mediaSession.metadata = MediaMetadata({
      'title': mediaInfo.title,
      if (mediaInfo.artist != null) 'artist': mediaInfo.artist,
      if (mediaInfo.artworkUrl != null) 'artwork': [
        { 'src': mediaInfo.artworkUrl, 'sizes': '512x512' },
      ],
    });
  }

  // 2. Set action handlers
  mediaSession.setActionHandler('play', () {
    play();
  });
  mediaSession.setActionHandler('pause', () {
    pause();
  });
  mediaSession.setActionHandler('seekto', (details) {
    final seekTime = details.seekTime; // seconds
    seekTo(Duration(milliseconds: (seekTime * 1000).round()));
  });
  mediaSession.setActionHandler('seekbackward', (details) {
    final offset = details.seekOffset ?? 10; // default 10 seconds
    final current = getPosition();
    seekTo(Duration(milliseconds: (current.inMilliseconds - (offset * 1000).round()).clamp(0, double.infinity).toInt()));
  });
  mediaSession.setActionHandler('seekforward', (details) {
    final offset = details.seekOffset ?? 10;
    final current = getPosition();
    seekTo(Duration(milliseconds: current.inMilliseconds + (offset * 1000).round()));
  });

  // 3. Set playback state
  _updateMediaSessionPlaybackState();

  // 4. Set position state
  _updateMediaSessionPositionState();
}

void _updateMediaSessionPlaybackState() {
  if (!_mediaSessionEnabled) return;
  final mediaSession = web.window.navigator.mediaSession;
  if (mediaSession == null) return;
  mediaSession.playbackState = _videoElement.paused ? 'paused' : 'playing';
}

void _updateMediaSessionPositionState() {
  if (!_mediaSessionEnabled) return;
  final mediaSession = web.window.navigator.mediaSession;
  if (mediaSession == null) return;
  final duration = _videoElement.duration;
  if (duration.isFinite && duration > 0) {
    mediaSession.setPositionState({
      'duration': duration,
      'playbackRate': _videoElement.playbackRate,
      'position': _videoElement.currentTime,
    });
  }
}

void _teardownMediaSession() {
  final mediaSession = web.window.navigator.mediaSession;
  if (mediaSession == null) return;
  mediaSession.metadata = null;
  mediaSession.playbackState = 'none';
  for (final action in ['play', 'pause', 'seekto', 'seekbackward', 'seekforward']) {
    mediaSession.setActionHandler(action, null);
  }
}
```

**Hook into existing play/pause/seek events** to keep MediaSession state in sync:

- In `play()` → call `_updateMediaSessionPlaybackState()` after play resolves
- In `pause()` → call `_updateMediaSessionPlaybackState()`
- In `seekTo()` → call `_updateMediaSessionPositionState()`
- In the `onPlay`/`onPause` listeners → call `_updateMediaSessionPlaybackState()`
- Periodically (or on `timeupdate` event) → call `_updateMediaSessionPositionState()`

### 2E. VideoPlayerPlugin overrides (`video_player_web.dart`)

```dart
@override
Future<void> enableBackgroundPlayback(int playerId, {MediaInfo? mediaInfo}) async {
  _player(playerId).enableMediaSession(mediaInfo);
}

@override
Future<void> disableBackgroundPlayback(int playerId) async {
  _player(playerId).disableMediaSession();
}
```

### 2F. Compatibility checks

1. **Feature detection** — `navigator.mediaSession` may be `undefined` in older browsers. Guard all access.
2. **Firefox** — Exposes the API but has no user-facing media control UI on desktop. Still works on Android Firefox.
3. **Safari** — Supports MediaSession from version 15+. Metadata and action handlers work on macOS and iOS Safari.
4. **Artwork** — Some browsers require CORS-accessible artwork URLs. Document this.
5. **Multiple players** — Only one `navigator.mediaSession` exists per page. If multiple players call `enableBackgroundPlayback`, the last one wins. This matches the single-session model on Android/iOS.

---

## Part 3: Auto-PiP

### 3A. How auto-PiP works on the web

Auto-PiP on the web is achieved through the **MediaSession `enterpictureinpicture` action handler**. When registered:

1. User switches to another tab while video is playing
2. Browser detects the tab is no longer visible and the video has an active media session
3. Browser invokes the `enterpictureinpicture` action handler
4. The handler calls `video.requestPictureInPicture()` (no user gesture required in this context — the browser provides the activation)
5. When user switches back, the PiP window **automatically closes**

**Browser support:**
- Chrome 120+: Works for `getUserMedia` streams
- **Chrome 133+**: Works for regular video playback (this is what we need)
- Edge: Same as Chrome (Chromium-based)
- Safari: Not supported
- Firefox: Not supported

The `enterPictureInPictureReason` property in the action details tells you why PiP was triggered:
- `"useraction"` — user explicitly triggered PiP via browser UI
- `"contentoccluded"` — browser auto-triggered because tab was switched/minimized

### 3B. Implementation

**Prerequisite:** MediaSession must be set up (Part 2). Auto-PiP on the web is a MediaSession feature.

```dart
bool _autoEnterPip = false;
web.EventHandler? _enterpipHandler;

void setAutoEnterPip(bool enabled) {
  _autoEnterPip = enabled;
  final mediaSession = web.window.navigator.mediaSession;
  if (mediaSession == null) return;

  if (enabled) {
    mediaSession.setActionHandler('enterpictureinpicture', (details) {
      // Auto-enter PiP when browser requests it (tab switch, etc.)
      _videoElement.requestPictureInPicture();
    });
  } else {
    mediaSession.setActionHandler('enterpictureinpicture', null);
  }
}
```

### 3C. Compatibility & fallback for auto-PiP

Since auto-PiP via MediaSession `enterpictureinpicture` requires Chrome 133+, and there's no equivalent on Safari/Firefox, the fallback options are:

1. **Page Visibility API fallback** — Listen to `document.visibilitychange` event:
   ```dart
   document.addEventListener('visibilitychange', () {
     if (document.visibilityState == 'hidden' && _autoEnterPip) {
       // Attempt PiP — BUT this will fail without user gesture in most browsers
       video.requestPictureInPicture().catch(() {});
     }
   });
   ```
   **Problem:** `requestPictureInPicture()` requires user activation, so this will throw `NotAllowedError` on browsers that don't support the MediaSession `enterpictureinpicture` action.

2. **Recommendation:** Register the MediaSession `enterpictureinpicture` handler when `setAutoEnterPip(true)` is called. On browsers that don't support it, auto-PiP simply won't trigger — no error, just a no-op. The `visibilitychange` fallback is **not reliable** and should not be used.

3. **Detection:** We can expose whether auto-PiP is likely supported:
   ```dart
   bool get isAutoEnterPipSupported {
     // Check if MediaSession supports the enterpictureinpicture action
     // There's no direct detection API — we just set the handler and
     // hope for the best. Chrome 133+ will invoke it.
     return isPipSupported; // Basic requirement
   }
   ```

### 3D. VideoPlayerPlugin override

```dart
@override
Future<void> setAutoEnterPip(int playerId, bool enabled) async {
  _player(playerId).setAutoEnterPip(enabled);
}
```

---

## Part 4: Implementation Order & Dependencies

```
Phase 1: JS Interop Foundation
├── Add PiP interop extensions to pkg_web_tweaks.dart
├── Add MediaSession interop extensions to pkg_web_tweaks.dart
└── Verify which APIs are already in package:web

Phase 2: PiP Core
├── Add PiP methods to VideoPlayer class
├── Add PiP event listeners (enterpictureinpicture / leavepictureinpicture)
├── Add PiP overrides to VideoPlayerPlugin
├── Error handling + compatibility guards
└── Tests

Phase 3: MediaSession
├── Add MediaSession setup/teardown to VideoPlayer
├── Hook into play/pause/seek for state sync
├── Add enableBackgroundPlayback/disableBackgroundPlayback overrides
├── Position state updates (timeupdate listener)
└── Tests

Phase 4: Auto-PiP
├── Add enterpictureinpicture action handler registration
├── Wire setAutoEnterPip override
├── Ensure MediaSession is set up before auto-PiP can work
│   (auto-PiP depends on MediaSession — if enableBackgroundPlayback
│    hasn't been called, auto-PiP should still set up a minimal
│    MediaSession with just the enterpictureinpicture handler)
└── Tests

Phase 5: Integration & Edge Cases
├── Multiple players — only one can be in PiP at a time on web
│   (entering PiP for player B should exit PiP for player A)
├── Dispose cleanup — exit PiP and teardown MediaSession on dispose
├── Interaction with VideoPlayerWebOptions.controls.allowPictureInPicture
├── Cross-browser testing (Chrome, Safari, Edge, Firefox)
└── Update example app to demonstrate web PiP + MediaSession
```

---

## Part 5: Known Limitations & Differences from Native

| Aspect | Native (iOS/Android) | Web |
|--------|---------------------|-----|
| `exitPip()` | iOS: works. Android: no-op (system-controlled) | Works via `document.exitPictureInPicture()` |
| `wasDismissed` | iOS/Android: detectable | Web: **not detectable** — the `leavepictureinpicture` event doesn't distinguish close vs. expand |
| `pipWindowSize` | Available on both | Available from `PictureInPictureWindow.width/height` on enter; not available on leave |
| Auto-PiP | iOS 14.2+ / Android 12+ | Chrome 133+ only (via MediaSession action) |
| MediaSession | Full control | Single session per page; limited action set vs. native |
| Background playback | Requires service/audio session config | Browsers handle natively (audio continues in background tab) |
| Artwork | Local or remote | Must be CORS-accessible URL |
| PiP controls | Custom actions | Browser-provided based on MediaSession action handlers |
| Firefox PiP | N/A | Non-standard, not programmable — `isPipSupported()` returns `false` |

---

## Part 6: Testing Strategy

### Unit / Integration tests

1. **isPipSupported** — mock `document.pictureInPictureEnabled` returning `true`/`false`/`undefined`
2. **enterPip** — verify `requestPictureInPicture()` is called; verify error handling for `NotAllowedError`, `InvalidStateError`, `SecurityError`
3. **exitPip** — verify `document.exitPictureInPicture()` is called; verify no-op when not in PiP
4. **isPipActive** — verify state tracks correctly through enter/leave events
5. **PiP events** — verify `VideoEventType.pipStateChanged` is emitted with correct `isPipActive` and `pipWindowSize`
6. **MediaSession metadata** — verify `navigator.mediaSession.metadata` is set correctly from `MediaInfo`
7. **MediaSession actions** — verify action handlers are registered and invoke correct VideoPlayer methods
8. **MediaSession state sync** — verify `playbackState` and `positionState` update on play/pause/seek
9. **Auto-PiP** — verify `enterpictureinpicture` handler is registered/unregistered
10. **Dispose** — verify PiP is exited and MediaSession is torn down
11. **Multiple players** — verify entering PiP for one player while another is in PiP

### Manual browser testing

- Chrome (primary target): PiP, auto-PiP, MediaSession
- Safari: PiP (no auto-PiP), MediaSession
- Edge: Same as Chrome
- Firefox: Verify graceful degradation (isPipSupported returns false)