# Video Player Fork: Background Playback + PiP Implementation Plan

## Current State Summary

The official `video_player` (v2.11.0) uses:
- **Android:** Media3/ExoPlayer 1.9.2 (latest) - basic playback only
- **iOS:** AVPlayer/AVFoundation - basic playback only
- **Communication:** Pigeon-generated type-safe channels (v26.x)
- **Rendering:** Texture-based (SurfaceProducer/CVPixelBuffer) and PlatformView

What's missing: No MediaSession, no foreground Service, no PiP, no caching, no media notifications.

---

## Phase 1: Android — MediaSessionService + PiP

### Goal
Move ExoPlayer into a `MediaSessionService` so it survives app backgrounding. Add PiP support on the Activity.

### Files to Create

#### 1. `PlaybackService.java` (new)
Location: `video_player_android/android/src/main/java/io/flutter/plugins/videoplayer/service/`

```
MediaSessionService subclass:
- Hosts ExoPlayer instance (moved from VideoPlayer)
- Creates MediaSession automatically
- Android auto-manages: notification, audio focus, lock screen controls, Bluetooth
- Lifecycle: starts foreground when playing, stops after ~10min idle

Key methods:
  onCreate()     → Build ExoPlayer, create MediaSession
  onGetSession() → Return session for external controllers
  onDestroy()    → Release player + session
```

#### 2. `ServiceVideoPlayer.java` (new)
Location: `video_player_android/android/src/main/java/io/flutter/plugins/videoplayer/service/`

```
New VideoPlayer subclass (extends abstract VideoPlayer):
- Gets ExoPlayer from PlaybackService instead of creating it locally
- Connects to service via MediaController
- Attaches/detaches SurfaceProducer based on lifecycle
- Handles PiP transitions (Activity visible → PiP → background → foreground)

Key behavior:
  - On foreground: attach surface, render video
  - On PiP: surface still attached (Activity partially visible)
  - On full background: detach surface, audio continues via Service
  - On return: reattach surface, video resumes instantly
```

#### 3. `PipHandler.java` (new)
Location: `video_player_android/android/src/main/java/io/flutter/plugins/videoplayer/pip/`

```
Manages PiP on FlutterActivity:
  enterPip()        → Build PictureInPictureParams (16:9), call enterPictureInPictureMode()
  isPipSupported()  → Check API 26+, hasSystemFeature(PIP)
  isPipActive()     → Query activity.isInPictureInPictureMode()
  setAutoEnter()    → Android 12+: setAutoEnterEnabled(true) on home gesture

Lifecycle integration:
  onUserLeaveHint()                    → Auto-enter PiP if video playing
  onPictureInPictureModeChanged()      → Notify Flutter of PiP state
```

### Files to Modify

#### 4. `VideoPlayerPlugin.java` — Major Changes
```
- Add ActivityAware interface (needed for PiP — requires Activity reference)
- Create PlaybackService connection on plugin attach
- Route player creation to ServiceVideoPlayer when background playback enabled
- Add PiP methods to plugin API
- Handle activity lifecycle callbacks for PiP
```

#### 5. `VideoPlayer.java` — Minor Changes
```
- Make ExoPlayer creation pluggable (already has ExoPlayerProvider)
- Add method to detach/reattach surface without disposing player
- Add background playback state tracking
```

#### 6. `pigeons/messages.dart` — Add PiP + Background Messages
```dart
// New methods on AndroidVideoPlayerApi:
void enableBackgroundPlayback(int playerId)
void disableBackgroundPlayback(int playerId)

// New PiP API:
bool isPipSupported()
void enterPip(int playerId)
bool isPipActive()
void setAutoEnterPip(bool enabled)

// New events:
class PipStateEvent extends PlatformVideoEvent {
  bool isInPipMode;
}

class BackgroundPlaybackEvent extends PlatformVideoEvent {
  bool isPlayingInBackground;
}
```

#### 7. `AndroidManifest.xml` — Add Permissions + Service
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />

<service
    android:name=".service.PlaybackService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true">
    <intent-filter>
        <action android:name="androidx.media3.session.MediaSessionService"/>
    </intent-filter>
</service>
```

#### 8. `build.gradle` — Add Media3 Session Dependency
```gradle
implementation "androidx.media3:media3-session:1.9.2"
```

---

## Phase 2: iOS — AVPictureInPictureController + Background Audio

### Goal
Add PiP via AVPictureInPictureController. Add background audio by detaching AVPlayerLayer when backgrounded.

### Files to Create

#### 1. `FVPPipController.m` (new)
Location: `video_player_avfoundation/darwin/.../Sources/video_player_avfoundation/`

```objc
Wraps AVPictureInPictureController:
  - initWithPlayerLayer: → Create AVPictureInPictureController
  - startPip / stopPip
  - isPipSupported (class method)
  - isPipActive

AVPictureInPictureControllerDelegate:
  - pictureInPictureControllerWillStartPictureInPicture:
  - pictureInPictureControllerDidStartPictureInPicture:
  - pictureInPictureControllerWillStopPictureInPicture:
  - pictureInPictureControllerDidStopPictureInPicture:
  - pictureInPictureController:failedToStartWithError:
  - pictureInPictureController:restoreUserInterfaceForStopWithCompletionHandler:

Notifies Flutter of PiP state changes via event channel.
```

#### 2. `FVPBackgroundAudioHandler.m` (new)
Location: `video_player_avfoundation/darwin/.../Sources/video_player_avfoundation/`

```objc
Manages background audio transitions:
  - Listens to UIApplication.didEnterBackgroundNotification
  - On background:
    - Check if PiP is active → if yes, do nothing (PiP manages itself)
    - If no PiP → detach AVPlayer from AVPlayerLayer (audio continues)
  - On foreground:
    - Reattach AVPlayer to AVPlayerLayer (video resumes)

MPNowPlayingInfoCenter setup:
  - Update now playing info (title, duration, position, artwork)
  - MPRemoteCommandCenter for play/pause/seek from lock screen
```

### Files to Modify

#### 3. `FVPVideoPlayer.m` — Add PiP + Background Support
```objc
Changes:
  - Add FVPPipController property
  - Add backgroundAudioEnabled flag
  - On dispose: clean up PiP controller
  - Expose AVPlayerLayer for PiP controller initialization
  - Add method: detachPlayerFromLayer / reattachPlayerToLayer
```

#### 4. `FVPVideoPlayerPlugin.m` — Add PiP API Methods
```objc
Changes:
  - Register for app lifecycle notifications
  - Add PiP methods to Pigeon API
  - Handle PiP state events → forward to Flutter
  - Setup MPNowPlayingInfoCenter on background enable
```

#### 5. `pigeons/messages.dart` — Add PiP Messages (iOS)
```dart
// Same PiP API as Android for consistency:
bool isPipSupported()
void startPip(int playerId)
void stopPip(int playerId)
bool isPipActive(int playerId)

// Background playback:
void enableBackgroundPlayback(int playerId, MediaInfo mediaInfo)
void disableBackgroundPlayback(int playerId)

// MediaInfo for lock screen:
class MediaInfo {
  String title;
  String? artist;
  String? artworkUrl;
  int durationMs;
}
```

---

## Phase 3: Platform Interface + Dart API

### Files to Modify

#### 1. `video_player_platform_interface.dart`
```dart
Add to VideoPlayerPlatform:
  // PiP
  Future<bool> isPipSupported()
  Future<void> enterPip(int playerId)
  Future<void> exitPip(int playerId)
  Future<bool> isPipActive(int playerId)
  Future<void> setAutoEnterPip(int playerId, bool enabled)

  // Background playback
  Future<void> enableBackgroundPlayback(int playerId, {MediaInfo? mediaInfo})
  Future<void> disableBackgroundPlayback(int playerId)

Add new event types to VideoEventType:
  pipStateChanged
  backgroundPlaybackStateChanged

Add to VideoEvent:
  bool? isPipActive
  bool? isPlayingInBackground

New class:
  MediaInfo { title, artist, artworkUrl, durationMs }
```

#### 2. `video_player.dart` (core package)
```dart
Add to VideoPlayerController:
  // PiP
  Future<bool> get isPipSupported
  Future<void> enterPip()
  Future<void> exitPip()
  Future<void> setAutoEnterPip(bool enabled)

  // Background playback
  Future<void> enableBackgroundPlayback({MediaInfo? mediaInfo})
  Future<void> disableBackgroundPlayback()

Add to VideoPlayerValue:
  bool isPipActive
  bool isPlayingInBackground

Modify _VideoAppLifeCycleObserver:
  - If backgroundPlayback enabled, don't pause on background
  - Let native layer handle the transition
```

#### 3. Android `android_video_player.dart`
```dart
Wire new pigeon methods to platform interface methods.
Handle new event types from event channel.
```

#### 4. iOS `avfoundation_video_player.dart`
```dart
Wire new pigeon methods to platform interface methods.
Handle new event types from event channel.
```

---

## Phase 4: Integration with App

### In common_dart

#### Modify `LessonVideoPlayerController`
```dart
- Drop pod_player dependency entirely
- Use VideoPlayerController directly (from fork)
- Call enableBackgroundPlayback() with lesson MediaInfo on init
- Call setAutoEnterPip(true) when video starts playing
- Listen to pip/background state changes → update UI state
```

### In app

#### Modify `lesson_layout_cubit.dart`
```dart
- Add PIP to LessonLayout enum
- Listen to VideoPlayerController pip events
- On PiP enter → emit PIP layout (simplified video-only)
- On PiP exit → emit DEFAULT layout
```

#### Modify `lesson_player.dart`
```dart
- In PIP layout: show only video surface, no overlay controls
- Normal layout: unchanged
```

#### Modify `video_lesson_screen.dart`
```dart
- Remove pod_player widget references
- Use VideoPlayer widget from fork directly
- Listen to layout cubit for PiP transitions
```

### Remove (no longer needed)
- `pod_player` dependency from pubspec.yaml
- `http_cache_stream` dependency (later, when native caching added)
- `safe_http_cache_manager.dart` (later)
- `cache_stream_helper.dart` (later)
- All planned hybrid files (video_background_audio_bridge, video_background_playback_cubit)

---

## Implementation Order

### Step 1: Android Background Playback (most impactful)
1. Add `media3-session` dependency to build.gradle
2. Create `PlaybackService.java`
3. Create `ServiceVideoPlayer.java`
4. Update AndroidManifest.xml
5. Update pigeon messages + regenerate
6. Wire through platform interface + Dart API
7. Test: background app → audio continues, foreground → video resumes

### Step 2: Android PiP
1. Create `PipHandler.java`
2. Add ActivityAware to VideoPlayerPlugin
3. Update pigeon messages + regenerate
4. Wire PiP API through Dart
5. Test: home button → PiP window, tap PiP → full app

### Step 3: iOS Background Audio
1. Create `FVPBackgroundAudioHandler.m`
2. Modify FVPVideoPlayer for layer detach/reattach
3. Add MPNowPlayingInfoCenter + MPRemoteCommandCenter
4. Test: lock screen → audio continues, unlock → video resumes

### Step 4: iOS PiP
1. Create `FVPPipController.m`
2. Wire to pigeon API
3. Handle PiP + background audio conflict (isPipActive guard)
4. Test: background → PiP, dismiss PiP → audio continues

### Step 5: App Integration
1. Drop pod_player, use fork's VideoPlayerController directly
2. Update LessonVideoPlayerController
3. Update layout cubit + lesson player for PiP layout
4. E2E testing

---

## Known Limitations to Accept

1. **iPhone PiP + lock screen:** Audio pauses when screen locked during PiP (Apple bug)
2. **iPad PiP + lock screen:** Works correctly (audio continues)
3. **Android pre-API 26:** No PiP support (graceful fallback to background audio only)
4. **First frame on resume:** ~100-200ms to reattach surface on Android, ~frame on iOS

## Future Enhancements (not in this plan)

1. Media3 `DownloadManager` for HLS offline downloads
2. Media3 `SimpleCache` to replace Dart caching layer
3. HLS adaptive bitrate streaming (already supported by Media3/AVPlayer, just needs content)
4. DRM support (Widevine/FairPlay)
