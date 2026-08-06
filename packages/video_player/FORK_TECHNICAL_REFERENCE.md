# Technical Reference for Fork Implementation

## Critical Flutter Integration Gotchas

### 1. FlutterActivity Lifecycle vs PiP

**The #1 risk.** Flutter's `FlutterActivity` is NOT a standard Android Activity when it comes to PiP.

**Problem:** When Android enters PiP, it calls `onPause()` on the Activity. Flutter's engine historically treated `onPause` as "app is inactive" and could pause rendering. In PiP mode, the Activity is still partially visible — rendering must continue.

**Solution:** Flutter 3.13+ added `onPictureInPictureModeChanged()` support. The FlutterActivity already handles this correctly IF:
- You override `onPictureInPictureModeChanged()` in your MainActivity
- You use `super.onPictureInPictureModeChanged()` to let FlutterActivity handle it
- The Flutter engine will keep rendering in PiP mode

**Verify in the app's MainActivity.kt** that it extends `FlutterActivity` (not `FlutterFragmentActivity` — PiP behaves differently with fragments).

**Key file to check:** `/Users/rwrz/projects/app/android/app/src/main/kotlin/.../MainActivity.kt`

### 2. Texture vs PlatformView for PiP

**Texture rendering (current default):** Video frames go through `SurfaceProducer` → Flutter texture. During PiP, the Flutter engine continues rendering these textures into the shrunk Activity window. This works BUT:
- The texture size doesn't auto-adjust for PiP's small window
- You may want to downscale during PiP for performance

**PlatformView rendering:** The native `SurfaceView` is embedded directly. During PiP, Android handles the SurfaceView natively — potentially smoother PiP transitions because no Flutter rendering pipeline in the middle.

**Recommendation:** Use `platformView` mode for PiP. The current `PlatformViewVideoPlayer.java` already works with ExoPlayer's `setVideoSurfaceView()`. In PiP mode, Android natively manages the SurfaceView in the mini window without Flutter involvement.

### 3. MediaSessionService and Flutter Engine

**Problem:** A `MediaSessionService` runs independently of the Activity. Flutter's engine is attached to the Activity. When the Activity is destroyed (full background), the Flutter engine may be detached or stopped.

**Solution:** The Service hosts ExoPlayer natively — it does NOT need Flutter's engine to continue playback. The communication flow is:
- Activity alive → Flutter communicates with Service via Pigeon/MethodChannel as normal
- Activity destroyed → Service continues audio playback natively, no Flutter involvement
- Activity recreated → Flutter reconnects to the existing Service and queries current state

**Critical:** The ExoPlayer instance must live in the Service, NOT be created by the Flutter plugin. The plugin just connects to it.

### 4. iOS: Texture Rendering and Background

**Problem:** `FVPTextureBasedVideoPlayer` uses a display link (`CADisplayLink`) to pump frames to Flutter's texture. When the app backgrounds, the display link stops (iOS suspends rendering). If the AVPlayer is still playing (audio-only), no frames are rendered — which is correct. BUT when returning to foreground, the display link must restart and the first frame must be delivered.

**The existing code already handles this** via `waitingForFrame` and `expectFrame()`. After a seek or resume, it signals the display link to run until a frame is delivered. On foreground return, calling `play()` or any state update will trigger `updatePlayingState()` which starts the display link.

**For PiP on iOS:** PiP uses `AVPictureInPictureController` which renders from `AVPlayerLayer`, NOT from Flutter's texture. So during PiP, Flutter's texture rendering can stop — PiP renders natively. When PiP ends and the user returns, Flutter's texture rendering resumes.

**Important:** PiP requires an `AVPlayerLayer` to be attached. The `FVPTextureBasedVideoPlayer` already creates an invisible AVPlayerLayer (for decoding). For PiP, this layer needs to be visible and sized correctly. Consider using `FVPVideoPlayer` (platform view mode) instead for PiP, or creating a separate visible AVPlayerLayer for PiP.

### 5. Flutter's WidgetsBindingObserver vs Native Lifecycle

**Problem:** Flutter has `WidgetsBindingObserver.didChangeAppLifecycleState()` which fires `paused`, `inactive`, `resumed`, etc. The current `_VideoAppLifeCycleObserver` in `video_player.dart` pauses video on `paused` state. With `allowBackgroundPlayback: true`, this observer is NOT created — good.

**BUT:** If consumers use their own `WidgetsBindingObserver` (like `video_lesson_screen.dart` might), they could accidentally pause the video on lifecycle changes. Make sure the Dart-side controller does NOT auto-pause when background playback is enabled.

### 6. Pigeon Code Generation

After modifying `pigeons/messages.dart`, regenerate with:
```bash
# In video_player_android/
dart run pigeon --input pigeons/messages.dart

# In video_player_avfoundation/
dart run pigeon --input pigeons/messages.dart
```

This generates:
- Android: `Messages.kt` (Kotlin)
- iOS: `messages.g.h` + `messages.g.m` (Objective-C)

The generated code must match the pigeon version in each package's dev_dependencies.

### 7. Event Channel Instance Naming

Each player gets its own event channel:
- Android: `dev.flutter.pigeon.video_player_android.VideoEventChannel.videoEvents.{instanceName}`
- iOS: `flutter.dev/videoPlayer/videoEvents{playerId}`

New PiP/background events should go through the SAME event channel (add new event types to the sealed class), NOT a separate channel. This keeps the architecture consistent.

---

## Current Architecture Quick Reference

### Android Files (all in `video_player_android/android/src/main/java/io/flutter/plugins/videoplayer/`)

| File | Role |
|---|---|
| `VideoPlayerPlugin.java` | Plugin entry, manages players, implements AndroidVideoPlayerApi |
| `VideoPlayer.java` | Abstract base, owns ExoPlayer, implements VideoPlayerInstanceApi |
| `texture/TextureVideoPlayer.java` | Texture rendering via SurfaceProducer |
| `platformview/PlatformViewVideoPlayer.java` | Native SurfaceView rendering |
| `platformview/PlatformVideoView.java` | SurfaceView wrapper (handles API-level quirks) |
| `VideoAsset.java` | Abstract media source factory (HttpVideoAsset, LocalVideoAsset, RtspVideoAsset) |
| `ExoPlayerEventListener.java` | Player.Listener → VideoPlayerCallbacks bridge |
| `VideoPlayerEventCallbacks.java` | Events → Pigeon event channel |
| `VideoPlayerCallbacks.java` | Callback interface |
| `VideoPlayerOptions.java` | Mix-with-others config |
| `QueuingEventSink.java` | Buffers events before listener attaches |

### iOS Files (all in `video_player_avfoundation/darwin/.../Sources/video_player_avfoundation/`)

| File | Role |
|---|---|
| `FVPVideoPlayerPlugin.m` | Plugin entry, manages players, implements AVFoundationVideoPlayerApi |
| `FVPVideoPlayer.m` | Base player, owns AVPlayer, KVO observers, playback control |
| `FVPTextureBasedVideoPlayer.m` | Texture rendering via display link + CVPixelBuffer |
| `FVPEventBridge.m` | Events → Flutter event channel (with queuing) |
| `FVPFrameUpdater.m` | Signals texture registry for new frames |
| `FVPAVFactory.m` | DI factory for AVFoundation objects |
| `FVPNativeVideoViewFactory.m` | PlatformView factory |
| `FVPCADisplayLink.m` | iOS display link wrapper |

### Key Dependencies

| Package | Android | iOS |
|---|---|---|
| Media3 ExoPlayer | 1.9.2 | N/A |
| Media3 HLS | 1.9.2 | N/A (AVPlayer native) |
| Media3 DASH | 1.9.2 | N/A |
| **Media3 Session** | **ADD: 1.9.2** | N/A |
| AVFoundation | N/A | Native framework |
| **AVKit (PiP)** | N/A | **ADD: import AVKit** |
| **MediaPlayer (NowPlaying)** | N/A | **ADD: import MediaPlayer** |

### Pigeon Definitions

| Platform | File | Pigeon Version |
|---|---|---|
| Android | `video_player_android/pigeons/messages.dart` | v26.1.5 |
| iOS | `video_player_avfoundation/pigeons/messages.dart` | v26.1.7 |

---

## Android MediaSessionService Pattern

The correct architecture (how YouTube/Spotify do it):

```
┌─────────────────────────────┐
│      PlaybackService        │  ← Foreground Service (survives Activity death)
│  ┌───────────────────────┐  │
│  │      ExoPlayer         │  │  ← Lives here, NOT in Activity
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │     MediaSession       │  │  ← Auto: notification, lock screen, Bluetooth
│  └───────────────────────┘  │
└─────────────────────────────┘
         ↕ MediaController
┌─────────────────────────────┐
│     FlutterActivity         │  ← Can be destroyed/recreated
│  ┌───────────────────────┐  │
│  │  VideoPlayerPlugin     │  │  ← Connects to Service via MediaController
│  │  (Pigeon channel)      │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │  SurfaceView/Texture   │  │  ← Attaches to Service's ExoPlayer for rendering
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │  PiP Handler           │  │  ← Activity-level PiP management
│  └───────────────────────┘  │
└─────────────────────────────┘
```

**State transitions:**
1. Foreground → ExoPlayer renders to SurfaceView/Texture via Activity
2. Home pressed → PiP (if supported) → Activity shrinks, rendering continues
3. PiP dismissed / Activity stopped → Service keeps ExoPlayer running (audio only)
4. User returns → Activity reconnects, re-attaches surface, video resumes

## iOS AVPlayer + PiP Pattern

```
┌─────────────────────────────┐
│     FVPVideoPlayer          │
│  ┌───────────────────────┐  │
│  │      AVPlayer          │  │  ← Single instance throughout
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │   AVPlayerLayer        │  │  ← For rendering + PiP source
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ AVPictureInPictureCtrl │  │  ← Controls PiP window
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ MPNowPlayingInfoCenter │  │  ← Lock screen info
│  │ MPRemoteCommandCenter  │  │  ← Lock screen controls
│  └───────────────────────┘  │
└─────────────────────────────┘
```

**State transitions:**
1. Foreground → AVPlayerLayer renders in Flutter view
2. Background → check isPictureInPictureActive:
   - YES → PiP manages rendering via AVPlayerLayer
   - NO → detach player from layer → audio continues
3. Lock screen → MPNowPlayingInfoCenter shows controls
4. Foreground return → reattach player to layer → video resumes

**The iOS gotcha:** PiP needs PlatformView mode (AVPlayerLayer embedded in UIView), NOT texture mode. In texture mode, the invisible AVPlayerLayer used for decoding cannot serve as PiP source in a reliable way. Use `VideoViewType.platformView` when PiP is needed.
