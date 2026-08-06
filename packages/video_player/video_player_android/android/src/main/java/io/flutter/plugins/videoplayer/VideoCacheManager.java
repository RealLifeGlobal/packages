// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.videoplayer;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.annotation.OptIn;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.database.StandaloneDatabaseProvider;
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor;
import androidx.media3.datasource.cache.SimpleCache;
import java.io.File;

/**
 * Singleton managing a {@link SimpleCache} instance for HLS segment caching.
 *
 * <p>Wrapping streaming data sources with a {@link
 * androidx.media3.datasource.cache.CacheDataSource.Factory} backed by this cache allows previously
 * fetched HLS segments to be served from disk on re-watch, avoiding redundant downloads.
 */
@UnstableApi
final class VideoCacheManager {
  private static final String CACHE_DIR_NAME = "video_player_cache";
  private static final long DEFAULT_MAX_CACHE_SIZE = 500L * 1024 * 1024; // 500 MB

  private static SimpleCache cache;
  private static StandaloneDatabaseProvider databaseProvider;
  private static long maxCacheSize = DEFAULT_MAX_CACHE_SIZE;
  private static boolean enabled = true;

  private VideoCacheManager() {}

  /**
   * Returns the shared {@link SimpleCache} instance, creating it lazily if needed.
   *
   * @param context application context.
   * @return the cache instance.
   */
  @NonNull
  static synchronized SimpleCache getCache(@NonNull Context context) {
    if (cache == null) {
      File cacheDir = new File(context.getCacheDir(), CACHE_DIR_NAME);
      if (!cacheDir.exists()) {
        cacheDir.mkdirs();
      }
      databaseProvider = new StandaloneDatabaseProvider(context);
      LeastRecentlyUsedCacheEvictor evictor = new LeastRecentlyUsedCacheEvictor(maxCacheSize);
      cache = new SimpleCache(cacheDir, evictor, databaseProvider);
    }
    return cache;
  }

  /** Returns whether caching is enabled. */
  static synchronized boolean isEnabled() {
    return enabled;
  }

  /** Enables or disables caching. */
  static synchronized void setEnabled(boolean enable) {
    enabled = enable;
  }

  /**
   * Sets the maximum cache size. Takes effect the next time the cache is created (after a {@link
   * #release()}).
   *
   * @param bytes maximum size in bytes.
   */
  static synchronized void setMaxCacheSize(long bytes) {
    maxCacheSize = bytes;
    // If cache is already running, release and let it be re-created with the new size.
    if (cache != null) {
      release();
    }
  }

  /** Clears all cached data. */
  static synchronized void clearCache(@NonNull Context context) {
    if (cache != null) {
      release();
    }
    // Delete the cache directory on disk.
    File cacheDir = new File(context.getCacheDir(), CACHE_DIR_NAME);
    SimpleCache.delete(cacheDir, /* databaseProvider= */ null);
  }

  /**
   * Returns the current cache size in bytes.
   *
   * @return size in bytes, or 0 if cache is not initialized.
   */
  static synchronized long getCacheSize() {
    if (cache == null) {
      return 0;
    }
    return cache.getCacheSpace();
  }

  /** Releases the cache instance. Should be called when the plugin is detached. */
  static synchronized void release() {
    if (cache != null) {
      cache.release();
      cache = null;
    }
    databaseProvider = null;
  }
}
