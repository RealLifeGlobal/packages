# Phase 2: Caching, Offline Downloads & Adaptive Bitrate Plan

## Current State

| Feature | Android | iOS |
|---------|---------|-----|
| HLS playback | Media3 `media3-exoplayer-hls` 1.9.2 | AVPlayer native HLS |
| Adaptive bitrate | ExoPlayer auto-selects (DefaultTrackSelector exists) | AVPlayer auto-selects |
| Native caching | None (`DefaultHttpDataSource` — no disk cache) | None (AVPlayer ignores HTTP cache headers) |
| Offline downloads | None | None |
| Background + PiP | Done | Done |

## Decisions Made

- **iOS HLS segment caching: deferred.** AVPlayer cannot be intercepted cleanly
  (no data source pipeline like Media3). Requires a local reverse proxy server.
  Detailed plan saved separately — see `IOS_HLS_CACHE_PLAN.md` (future phase).
- **Preview/MP4 caching: app-level concern.** Small preview videos (500KB-2MB MP4s)
  are handled by the app's own Dart-side download-to-file layer, not the plugin.
- **Cache control API: consistent across platforms.** iOS implements the same pigeon
  interface as Android but returns no-ops / zero values until the iOS cache is built.

---

## Feature 1: HLS Segment Caching (Android only, iOS no-ops)

Cache HLS segments to disk so re-watching doesn't re-download. Transparent to the player.

### Android — Media3 SimpleCache

**Complexity: Low.** SimpleCache is part of `media3-exoplayer` (already a dependency). The change is essentially wrapping one data source factory.

**Key change point:** `HttpVideoAsset.java:79` — currently:
```java
DataSource.Factory dataSourceFactory = new DefaultDataSource.Factory(context, initialFactory);
return new DefaultMediaSourceFactory(context).setDataSourceFactory(dataSourceFactory);
```

Becomes:
```java
DataSource.Factory dataSourceFactory = new DefaultDataSource.Factory(context, initialFactory);
DataSource.Factory cacheFactory = new CacheDataSource.Factory()
    .setCache(VideoCacheManager.getCache(context))
    .setUpstreamDataSourceFactory(dataSourceFactory);
return new DefaultMediaSourceFactory(context).setDataSourceFactory(cacheFactory);
```

#### New file: `VideoCacheManager.java`
Location: `io.flutter.plugins.videoplayer.cache/`

```
Singleton owning SimpleCache instance:
- getCache(Context) → lazy-init SimpleCache
  - Cache dir: context.getCacheDir() + "/video_player_cache"
  - Evictor: LeastRecentlyUsedCacheEvictor (default 500MB, configurable)
  - Database: StandaloneDatabaseProvider
- setMaxCacheSize(long bytes) → recreate evictor
- clearCache() → SimpleCache.delete()
- getCacheSize() → sum cache span sizes
- release() → close SimpleCache on plugin teardown
```

#### Modify: `HttpVideoAsset.java`
- `getMediaSourceFactory()` → wrap `DataSource.Factory` in `CacheDataSource.Factory`
- Pass `Context` is already available (method parameter)
- ~10 lines changed

#### Modify: `VideoPlayerPlugin.java`
- `onDetachedFromEngine()` → call `VideoCacheManager.release()`
- Wire new pigeon methods for cache control

### iOS — No-op implementation

iOS cache control methods return safe defaults to keep the API consistent:
- `getCacheSize()` → returns `0`
- `clearCache()` → no-op
- `setCacheMaxSize()` → no-op (store value for future use)
- `isCacheEnabled()` → returns `false`
- `setCacheEnabled()` → no-op

When the iOS HLS cache (reverse proxy) is built in a future phase, these methods
will be wired to the real implementation without any Dart API changes.

### Pigeon additions (both platforms):

```dart
// On AndroidVideoPlayerApi / AVFoundationVideoPlayerApi:
void setCacheMaxSize(int maxSizeBytes);
void clearCache();
int getCacheSize();
bool isCacheEnabled();
void setCacheEnabled(bool enabled);
```

### Platform interface additions:

```dart
Future<void> setCacheMaxSize(int maxSizeBytes);
Future<void> clearCache();
Future<int> getCacheSize();
Future<bool> isCacheEnabled();
Future<void> setCacheEnabled(bool enabled);
```

---

## Feature 2: Adaptive Bitrate Control API

Both platforms already do ABR automatically. This adds developer control: constrain quality, query available renditions, get current bitrate.

### Android implementation

**Already have `DefaultTrackSelector`** — stored in `VideoPlayer.java:38`. Just need to expose controls.

#### New methods on `VideoPlayer.java`:
```java
void setMaxBitrate(long maxBitrate) {
    trackSelector.setParameters(
        trackSelector.buildUponParameters()
            .setMaxVideoBitrate((int) maxBitrate)
            .build());
}

void setMaxResolution(int width, int height) {
    trackSelector.setParameters(
        trackSelector.buildUponParameters()
            .setMaxVideoSize(width, height)
            .build());
}

List<VideoQuality> getAvailableQualities() {
    // Iterate Tracks.getGroups() for TRACK_TYPE_VIDEO
    // Extract Format: width, height, bitrate, codecs
}

VideoQuality getCurrentQuality() {
    Format format = exoPlayer.getVideoFormat();
    // Return width, height, bitrate, codecs
}
```

### iOS implementation

#### New methods on `FVPVideoPlayer.m`:
```objc
- (void)setMaxBitrate:(double)maxBitrate {
    _player.currentItem.preferredPeakBitRate = maxBitrate;
}

- (void)setMaxResolution:(int)width height:(int)height {
    if (@available(iOS 11.0, *)) {
        _player.currentItem.preferredMaximumResolution = CGSizeMake(width, height);
    }
}

- (NSArray<VideoQuality *> *)getAvailableQualities {
    // iOS 15+: AVAssetVariant API
    // Older: parse master playlist or return empty (limited API)
}

- (VideoQuality *)getCurrentQuality {
    AVPlayerItemAccessLogEvent *event = _player.currentItem.accessLog.events.lastObject;
    // Return indicatedBitrate, observedBitrate, etc.
}
```

### Pigeon additions (both platforms):

```dart
class PlatformVideoQuality {
  int width;
  int height;
  int bitrate;      // bits per second
  String? codec;
  bool isSelected;
}

// On VideoPlayerInstanceApi:
List<PlatformVideoQuality> getAvailableQualities();
PlatformVideoQuality? getCurrentQuality();
void setMaxBitrate(int maxBitrateBps);
void setMaxResolution(int width, int height);
```

### Platform interface additions:

```dart
Future<List<VideoQuality>> getAvailableQualities(int playerId);
Future<VideoQuality?> getCurrentQuality(int playerId);
Future<void> setMaxBitrate(int playerId, int maxBitrateBps);
Future<void> setMaxResolution(int playerId, int width, int height);
```

### Dart API additions on `VideoPlayerController`:

```dart
Future<List<VideoQuality>> getAvailableQualities();
Future<VideoQuality?> getCurrentQuality();
Future<void> setMaxBitrate(int maxBitrateBps);
Future<void> setMaxResolution(int width, int height);
```

---

## Feature 3: HLS Offline Downloads

Download complete HLS streams for offline viewing. Most complex feature.

### Android — Media3 DownloadManager

**Complexity: Medium.** Media3 provides `DownloadManager`, `DownloadService`, and `DownloadHelper` that handle the hard parts (manifest parsing, segment scheduling, persistence).

#### Dependencies
Already included in `media3-exoplayer`. No new gradle dependencies.

#### New file: `VideoDownloadManager.java`
Location: `io.flutter.plugins.videoplayer.download/`

```
Singleton managing all downloads:
- init(Context) → create DownloadManager with:
  - Same SimpleCache from VideoCacheManager (shared cache!)
  - DatabaseProvider for download state persistence
  - DefaultDownloaderFactory with CacheDataSource.Factory
  - Max parallel downloads: 3

Methods:
  downloadHls(url, contentId, headers, formatHint)
    → DownloadHelper.forMediaItem() to resolve manifest
    → DownloadHelper.getTrackSelections() to pick quality
    → DownloadManager.addDownload(DownloadRequest)

  pauseDownload(contentId) → DownloadManager.setStopReason(contentId, MANUAL_STOP)
  resumeDownload(contentId) → DownloadManager.setStopReason(contentId, STOP_REASON_NONE)
  removeDownload(contentId) → DownloadManager.removeDownload(contentId)

  getDownloadState(contentId) → query Downloads database
    → returns: state (queued/downloading/completed/failed/removing),
               percentDownloaded, bytesDownloaded

  getAllDownloads() → list all tracked downloads

  isDownloaded(contentId) → check Download.STATE_COMPLETED
```

#### New file: `VideoDownloadService.java`
Location: `io.flutter.plugins.videoplayer.download/`

```
Extends Media3 DownloadService:
- Required for background download management
- Creates download notification
- Persists across process death

Manifest additions:
  <service android:name=".download.VideoDownloadService"
           android:foregroundServiceType="dataSync"
           android:exported="false">
    <intent-filter>
      <action android:name="com.google.android.exoplayer.downloadService"/>
    </intent-filter>
  </service>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
```

#### Offline playback integration
**Key insight:** Because downloads go into the same `SimpleCache`, offline playback is automatic. When `CacheDataSource` is configured (from Feature 1), it checks cache first. If content is fully cached (downloaded), no network request is made.

```java
// No special "offline player" needed. Same CacheDataSource.Factory
// automatically serves from cache if available.
// Just need to verify content is fully downloaded before attempting offline play.
```

**Important:** Downloaded content uses `NoOpCacheEvictor` (never auto-evict).
Streaming cache uses `LeastRecentlyUsedCacheEvictor`. Media3 handles this via
separate cache content metadata — downloaded content is marked as pinned.

### iOS — AVAssetDownloadURLSession

**Complexity: Medium-High.** Apple's approach is fundamentally different — downloads produce `.movpkg` bundles, not cache entries.

#### New file: `FVPDownloadManager.m`
Location: `Sources/video_player_avfoundation/`

```objc
Singleton managing HLS downloads:

Init:
  - Create AVAssetDownloadURLSession with background NSURLSessionConfiguration
  - Session identifier: "com.videoPlayer.hlsDownloads"
  - Delegate: self (AVAssetDownloadDelegate)

Download:
  downloadHLS:(NSURL *)url
    contentId:(NSString *)contentId
      headers:(NSDictionary *)headers
  {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:headerOptions];
    AVAggregateAssetDownloadTask *task =
      [session aggregateAssetDownloadTaskWithURLAsset:asset
                                  mediaSelections:@[preferredMediaSelection]
                                       assetTitle:contentId
                                assetArtworkData:nil
                                         options:nil];
    [task resume];
    // Store task → contentId mapping
  }

Pause:    task.suspend
Resume:   task.resume
Cancel:   task.cancel
Delete:   [[NSFileManager defaultManager] removeItemAtURL:storedLocation]

Storage:
  - willDownloadTo: callback provides .movpkg location
  - MUST persist relative path (URL.relativePath) in NSUserDefaults
    (absolute path changes between app launches!)
  - Key format: "videoPlayer.download.<contentId>"

Playback:
  - (AVURLAsset *)assetForDownload:(NSString *)contentId
  {
    NSString *relativePath = [defaults stringForKey:key];
    NSURL *url = [homeDir URLByAppendingPathComponent:relativePath];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url];

    // Verify playable offline
    if (asset.assetCache.playableOffline) return asset;
    return nil;
  }

Delegate callbacks (AVAssetDownloadDelegate):
  - willDownloadTo:      → persist .movpkg location
  - didLoad:totalTime:   → calculate progress, emit to Dart
  - didCompleteWithError: → emit completion/failure
```

#### Modify: `FVPVideoPlayerPlugin.m`
```objc
// New creation path for offline content:
- (int)createFromDownload:(NSString *)contentId {
    AVURLAsset *asset = [[FVPDownloadManager shared] assetForDownload:contentId];
    // Create player with local asset
    // Same flow as createForPlatformView/createForTextureView
}
```

#### Important iOS limitations:
1. **Only HLS** — progressive MP4 downloads need manual NSURLSession download (separate path)
2. **Storage location is opaque** — iOS chooses where to put .movpkg, you just persist the path
3. **.movpkg must not be moved** — keep at system-provided location
4. **Verify before playback** — check `assetCache.playableOffline` before presenting

### Pigeon additions (both platforms):

```dart
class DownloadRequest {
  String url;
  String contentId;       // Unique ID for this download
  Map<String, String>? httpHeaders;
  PlatformVideoFormat? formatHint;  // Android only
}

class DownloadState {
  String contentId;
  DownloadStatus status;  // queued, downloading, paused, completed, failed, removing
  double percentComplete; // 0.0 - 1.0
  int bytesDownloaded;
}

enum DownloadStatus {
  queued, downloading, paused, completed, failed, removing
}

// New event type:
class DownloadProgressEvent extends PlatformVideoEvent {
  String contentId;
  double percentComplete;
  DownloadStatus status;
}

// On AndroidVideoPlayerApi / AVFoundationVideoPlayerApi:
void startDownload(DownloadRequest request);
void pauseDownload(String contentId);
void resumeDownload(String contentId);
void cancelDownload(String contentId);
void removeDownload(String contentId);
DownloadState getDownloadState(String contentId);
List<DownloadState> getAllDownloads();
int createPlayerFromDownload(String contentId);  // returns playerId
```

### Platform interface additions:

```dart
Future<void> startDownload(DownloadRequest request);
Future<void> pauseDownload(String contentId);
Future<void> resumeDownload(String contentId);
Future<void> cancelDownload(String contentId);
Future<void> removeDownload(String contentId);
Future<DownloadState> getDownloadState(String contentId);
Future<List<DownloadState>> getAllDownloads();
Stream<DownloadProgress> downloadProgressFor(String contentId);
Future<int?> createPlayerFromDownload(String contentId);
```

---

## Implementation Order

| Step | Feature | Platform | Effort | Notes |
|------|---------|----------|--------|-------|
| 1 | SimpleCache + cache API | Android (iOS no-ops) | 1-2 days | Highest ROI, ~15 lines of real code + no-op stubs |
| 2 | ABR control API | Both | 2-3 days | Mostly pigeon wiring, platforms already support it |
| 3 | DownloadManager | Android | 2-3 days | Media3 handles heavy lifting, shares SimpleCache |
| 4 | AVAssetDownload | iOS | 3-4 days | .movpkg management, persistence |

### Step 1: Android SimpleCache + consistent API
- Android: `VideoCacheManager` singleton + `CacheDataSource.Factory` in `HttpVideoAsset`
- iOS: no-op implementations of cache control methods (returns 0/false)
- Pigeon + platform interface: cache control methods on both platforms
- Immediate benefit: all Android HLS content auto-cached

### Step 2: ABR control API
- Can run in parallel with Step 1
- Both platforms already have the underlying capabilities
- Android: `DefaultTrackSelector` parameter setting
- iOS: `preferredPeakBitRate` / `preferredMaximumResolution`

### Step 3: Android DownloadManager
- Depends on Step 1 (shares `SimpleCache` instance)
- Media3 `DownloadManager` + `DownloadService` + `DownloadHelper`
- Downloaded content auto-plays via existing `CacheDataSource` — no separate offline player

### Step 4: iOS AVAssetDownload
- Independent of Steps 1-3 (different storage model — .movpkg, not cache entries)
- `AVAssetDownloadURLSession` + `AVAggregateAssetDownloadTask`
- Persist .movpkg relative paths in NSUserDefaults

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│                    Dart Layer                        │
│  VideoPlayerController                               │
│    .setMaxBitrate()  .startDownload()  .clearCache() │
│    .getAvailableQualities()  .createFromDownload()   │
└──────────────┬──────────────────────┬────────────────┘
               │ Pigeon               │ Pigeon
    ┌──────────▼──────────┐ ┌────────▼────────────────┐
    │    Android Native    │ │      iOS Native          │
    │                      │ │                          │
    │  ┌────────────────┐  │ │  Cache API = no-ops     │
    │  │ VideoCacheMgr  │  │ │  (until future phase)   │
    │  │  SimpleCache   │  │ │                          │
    │  │  LRU Evictor   │  │ │  ABR:                   │
    │  └───────┬────────┘  │ │  preferredPeakBitRate   │
    │          │            │ │  preferredMaxResolution │
    │  ┌───────▼────────┐  │ │                          │
    │  │ CacheDataSrc   │  │ │  ┌──────────────────┐   │
    │  │  Factory       │  │ │  │ FVPDownloadMgr   │   │
    │  └───────┬────────┘  │ │  │ AVAssetDownload  │   │
    │          │            │ │  │ URLSession       │   │
    │  ┌───────▼────────┐  │ │  │ .movpkg storage  │   │
    │  │ DownloadMgr    │  │ │  └──────────────────┘   │
    │  │ (shared cache) │  │ │                          │
    │  └────────────────┘  │ │                          │
    └──────────────────────┘ └─────────────────────────┘
```

## Known Risks

1. **Shared cache on Android** — SimpleCache is shared between streaming cache and DownloadManager. Downloaded content must be marked as non-evictable (Media3 handles this via `ContentMetadataMutations`).

2. **Download notifications on Android** — `VideoDownloadService` shows its own notification separate from `PlaybackService`. Need to ensure they don't conflict.

3. **iOS .movpkg persistence** — Absolute paths change between app installs. Must store `relativePath`, not absolute path. Must handle migration if app is restored from backup.

4. **Progressive MP4 offline** — `AVAssetDownloadURLSession` only works with HLS. For MP4 offline, need separate NSURLSession download + `file://` playback. Out of scope for this phase — handled by app-level Dart code.

5. **iOS ABR quality listing** — `AVAssetVariant` requires iOS 15+. On older iOS, `getAvailableQualities()` returns an empty list. `setMaxBitrate`/`setMaxResolution` work on all supported iOS versions.

## Future: iOS HLS Segment Cache

Detailed plan for the Media3-inspired reverse proxy cache on iOS is in
`IOS_HLS_CACHE_PLAN.md`. When implemented, the no-op cache methods on iOS
will be wired to the real `HLSSimpleCache` implementation with zero Dart API changes.
