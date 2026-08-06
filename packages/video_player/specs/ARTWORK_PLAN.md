# Notification Artwork / Thumbnail — Technical Reference

## Current Implementation (what we've done)

Both platforms already accept `artworkUrl` in `PlatformMediaInfo` via pigeon. We wired it up:

### Android
- `PlaybackService.setPlayer()` now accepts title, artist, artworkUrl
- Sets `MediaMetadata.artworkUri` on the current `MediaItem` via `ExoPlayer.replaceMediaItem()` (no playback interruption)
- Media3's `DefaultMediaNotificationProvider` automatically:
  - Fetches the bitmap from the URI using `CacheBitmapLoader` -> `DataSourceBitmapLoader`
  - Sets it as the notification large icon
  - On Android 13+, the OS applies artwork as the notification background with color extraction (MediaStyle)

### iOS
- `FVPBackgroundAudioHandler` downloads artwork asynchronously via `NSURLSession`
- Creates `MPMediaItemArtwork` and sets `MPMediaItemPropertyArtwork` on `nowPlayingInfo`
- Includes staleness check (URL comparison) for rapid re-enable calls
- Artwork appears on lock screen and Control Center

## How `audio_service` does it (reference)

Source: https://github.com/ryanheise/audio_service

### Architecture
- Flutter side downloads artwork via `flutter_cache_manager`, passes local file path to native
- Native side loads bitmap from file via `BitmapFactory.decodeFile()`
- Uses `LruCache<String, Bitmap>` sized at 1/8 of available VM memory

### Notification artwork (AudioService.java)
```java
// Three things set with the artwork bitmap:
builder.setLargeIcon(artBitmap);  // thumbnail in notification

// These two let the OS use it as notification background/tinting:
mediaMetadata = new MediaMetadataCompat.Builder(mediaMetadata)
    .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, artBitmap)
    .putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, artBitmap)
    .build();
mediaSession.setMetadata(mediaMetadata);
```

### Configuration exposed to Flutter
- `artDownscaleWidth` / `artDownscaleHeight` — reduce bitmap memory usage
- `notificationColor` — explicit notification tint override
- `androidNotificationIcon` — custom small icon resource
- `androidShowNotificationBadge` — badge visibility toggle

## Media3 vs audio_service (old MediaSession compat)

| Aspect | audio_service (MediaSessionCompat) | Our implementation (Media3) |
|--------|-----------------------------------|-----------------------------|
| Notification building | Manual `NotificationCompat.Builder` | Automatic via `DefaultMediaNotificationProvider` |
| Artwork loading | Manual `BitmapFactory.decodeFile()` from cached file | Automatic via `CacheBitmapLoader` from URI |
| Large icon | Explicit `setLargeIcon(bitmap)` | Automatic from `MediaMetadata.artworkUri` |
| Background/tinting | `METADATA_KEY_ALBUM_ART` on MediaSession | Automatic on Android 13+ via MediaStyle |
| Bitmap cache | Custom `LruCache` (1/8 VM memory) | Built-in `CacheBitmapLoader` wrapper |
| Downscaling | Manual via `BitmapFactory.Options.inSampleSize` | Not exposed (Media3 handles internally) |

## What we get for free with Media3

Media3's `DefaultMediaNotificationProvider` already handles the "beautiful" expanded notification:
- Artwork as large icon
- System-level color extraction from artwork for notification background (Android 13+)
- Caching via `CacheBitmapLoader`
- Play/pause, seek controls

## Potential enhancements (not yet implemented)

1. **Art downscaling config** — expose width/height to reduce memory on low-end devices
2. **Notification color override** — let Flutter set an explicit tint color
3. **Custom small icon** — allow overriding the notification small icon resource
4. **Notification channel config** — expose channel name/description to Flutter
5. **Custom `MediaNotification.Provider`** — for full control over notification layout if Media3 defaults aren't sufficient

## Known issues

- Android 13 has a framework bug where artworks with transparent backgrounds overlap in the notification (fixed in Android 14+). Workaround: convert bitmap to `RGB_565` format. See: https://github.com/androidx/media/issues/939
