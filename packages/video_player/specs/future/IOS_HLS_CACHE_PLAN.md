# Phase 2: HLS Segment Caching — Updated Plan
## Inspired by Media3 SimpleCache Architecture

---

## What Changed From Previous Plan

The original iOS plan used a **sophisticated proxy** as the primary unit of work.
This update flips that: the **cache storage layer is the primary unit**, and the proxy
becomes thin HTTP plumbing on top of it.

This mirrors exactly how Media3 works on Android:
- Android: `CacheDataSource` (smart) → `SimpleCache` (storage) — no proxy needed
- iOS: `NWListener proxy` (thin) → `HLSSimpleCache` (smart, Media3-inspired) — same storage model

---

## Android — No Changes

Android's plan is unchanged. Media3's `SimpleCache` + `CacheDataSource.Factory`
is already the right implementation. It requires ~15 lines of code in
`HttpVideoAsset.java`. See original plan.

**Key reminder:** Use `NoOpCacheEvictor` for downloaded content (never
auto-evict) and `LeastRecentlyUsedCacheEvictor` for streaming cache only.

---

## iOS — Revised Architecture

### The Core Insight From Media3

Media3 never uses a proxy. Instead it inserts a `CacheDataSource` into
ExoPlayer's data pipeline — a layer that intercepts byte requests, checks cache,
and falls through to network on miss. iOS cannot do this because AVPlayer is a
black box with no data source interface.

But the **storage model** is fully portable. The proxy on iOS becomes thin
and dumb. All the intelligence lives in the cache layer.

```
ANDROID (no proxy needed):
ExoPlayer → CacheDataSource → [cache hit] FileDataSource → disk
                            → [cache miss] TeeDataSource → HttpDataSource + SimpleCache

iOS (proxy required, but thin):
AVPlayer → NWListener proxy (50 lines) → HLSSimpleCache (200 lines, Media3-inspired)
                                       → [cache hit] read file from disk
                                       → [cache miss] fetch R2 + write to disk simultaneously
```

---

## Media3 Concepts to Port to Swift

### 1. CacheSpan → `HLSCacheSpan`

In Media3, a CacheSpan is a byte range within a resource that may or may not be
cached. For HLS, this maps perfectly to segments — each `.m4s` is a natural
cache span. One file = one segment = one span. No byte-range arithmetic.

```swift
struct HLSCacheSpan {
    let cacheKey: String        // stable key (URL without query params)
    let fileName: String        // actual file on disk
    let length: Int             // bytes
    let lastAccessTime: Date    // for LRU eviction
    let isFullyCached: Bool     // always true for completed segments
}
```

### 2. CacheKeyFactory → `HLSCacheKeyFactory`

Media3 separates cache key from URL. Critical for R2 signed URLs where the same
segment gets a different `?X-Amz-Signature=...` on every request.

```swift
struct HLSCacheKeyFactory {
    /// Strips query params to produce a stable cache key.
    /// "https://r2.example.com/videos/abc/480p/seg001.m4s?X-Amz-Signature=xyz"
    /// → "https://r2.example.com/videos/abc/480p/seg001.m4s"
    static func cacheKey(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }
}
```

### 3. FLAG_BLOCK_ON_CACHE → Per-key mutex (`HLSCacheLock`)

Media3's `FLAG_BLOCK_ON_CACHE` prevents two simultaneous reads of the same
segment from both triggering network requests. One waits; the other serves from
the cache written by the first.

```swift
actor HLSCacheLock {
    private var lockedKeys: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func lock(_ key: String) async {
        if lockedKeys.contains(key) {
            await withCheckedContinuation { continuation in
                waiters[key, default: []].append(continuation)
            }
        } else {
            lockedKeys.insert(key)
        }
    }

    func unlock(_ key: String) {
        lockedKeys.remove(key)
        waiters.removeValue(forKey: key)?.forEach { $0.resume() }
    }
}
```

### 4. TeeDataSource → Simultaneous write-while-serve

Media3's `TeeDataSource` writes bytes to cache while simultaneously serving them
to the player. On iOS the proxy does this: it fetches from R2, writes each chunk
to disk, and forwards to AVPlayer in the same stream. No "download then serve"
delay.

```swift
// In HLSSimpleCache.fetchAndCache():
func fetchAndCache(url: URL, respondTo connection: NWConnection) async {
    let key = HLSCacheKeyFactory.cacheKey(for: url)
    await cacheLock.lock(key)
    defer { Task { await cacheLock.unlock(key) } }

    var accumulated = Data()
    // Stream from R2, accumulate bytes, forward to AVPlayer simultaneously
    for try await chunk in URLSession.shared.bytes(from: url).0 {
        accumulated.append(chunk)
        // Forward chunk to AVPlayer connection as it arrives (streaming response)
    }
    // Write complete segment to disk once fully received
    diskCache.write(accumulated, forKey: key)
}
```

### 5. LeastRecentlyUsedCacheEvictor → `HLSCacheEvictor`

Identical logic to Media3 — evict least recently accessed spans when over
size limit. Runs after every write.

```swift
struct HLSCacheEvictor {
    let maxBytes: Int   // default 500MB for streaming cache

    func evictIfNeeded(from index: inout [String: HLSCacheSpan], cacheDir: URL) {
        let total = index.values.reduce(0) { $0 + $1.length }
        guard total > maxBytes else { return }

        let sorted = index.values.sorted { $0.lastAccessTime < $1.lastAccessTime }
        var freed = 0
        let target = total - maxBytes

        for span in sorted {
            try? FileManager.default.removeItem(
                at: cacheDir.appendingPathComponent(span.fileName))
            index.removeValue(forKey: span.cacheKey)
            freed += span.length
            if freed >= target { break }
        }
    }
}
```

### 6. StandaloneDatabaseProvider → `HLSCacheIndex`

Media3 persists the cache index to SQLite so it survives process death and app
restarts. On iOS, persist to a JSON file in the same cache directory.
Rebuilt from disk on launch if the index file is missing (same fallback as Media3).

```swift
actor HLSCacheIndex {
    private var spans: [String: HLSCacheSpan] = [:]   // cacheKey → span
    private let indexURL: URL

    // Persist index to disk (called after every write/eviction)
    func save() throws { ... }

    // Load index from disk on launch
    func load() throws { ... }

    // Fallback: rebuild from disk if index file missing/corrupt
    func rebuildFromDisk(cacheDir: URL) { ... }
}
```

---

## Revised iOS File Structure

### New files (all Swift, zero external dependencies)

```
Sources/video_player_avfoundation/cache/
├── HLSCacheKeyFactory.swift      ~30 lines   URL → stable cache key
├── HLSCacheSpan.swift            ~20 lines   Cache entry model
├── HLSCacheLock.swift            ~40 lines   Per-key mutex (FLAG_BLOCK_ON_CACHE)
├── HLSCacheIndex.swift           ~80 lines   Persistent index (StandaloneDatabaseProvider equivalent)
├── HLSCacheEvictor.swift         ~50 lines   LRU eviction
├── HLSSimpleCache.swift         ~120 lines   Facade (SimpleCache equivalent) — read/write/evict
├── HLSProxyServer.swift          ~80 lines   NWListener HTTP server (thin — just plumbing)
└── HLSProxyServerBridge.swift    ~15 lines   @objc bridge for FVPVideoPlayerPlugin.m
```

**~435 lines total across 8 files.**

Compare to original plan: ~315 lines across 4 files but with a monolithic proxy
doing too much. This separation mirrors Media3's own package structure and makes
each component independently testable.

### Modified files

```
FVPVideoPlayerPlugin.m   +5 lines   Start proxy, swap URL for HLS
```

---

## Detailed Component Responsibilities

### `HLSSimpleCache` (the central facade)

Direct equivalent of Media3's `SimpleCache`. All other components are injected.

```swift
final class HLSSimpleCache {
    static let shared = HLSSimpleCache()

    private let cacheDir: URL
    private let index: HLSCacheIndex
    private let evictor: HLSCacheEvictor
    private let lock: HLSCacheLock
    private let ioQueue = DispatchQueue(label: "hls.cache.io",
                                        attributes: .concurrent)

    // Read — equivalent to CacheDataSource cache hit path
    func data(for url: URL) async -> Data? {
        let key = HLSCacheKeyFactory.cacheKey(for: url)
        guard let span = await index.span(for: key) else { return nil }
        let fileURL = cacheDir.appendingPathComponent(span.fileName)
        let data = try? Data(contentsOf: fileURL)
        if data != nil { await index.updateAccessTime(for: key) }
        return data
    }

    // Write — equivalent to TeeDataSource write path
    func store(_ data: Data, for url: URL) async {
        let key = HLSCacheKeyFactory.cacheKey(for: url)
        let fileName = key.sha256() + ".m4s"
        let fileURL = cacheDir.appendingPathComponent(fileName)
        try? data.write(to: fileURL, options: .atomic)
        let span = HLSCacheSpan(cacheKey: key, fileName: fileName,
                                length: data.count, lastAccessTime: Date(),
                                isFullyCached: true)
        await index.set(span, for: key)
        await index.save()
        evictor.evictIfNeeded(...)
    }

    // Cache management API (exposed via Pigeon)
    func clearAll() async { ... }
    func currentSizeBytes() async -> Int { ... }
    func removeContent(for url: URL) async { ... }
}
```

### `HLSProxyServer` (thin HTTP plumbing)

All cache logic delegated to `HLSSimpleCache`. The proxy does only two things:
parse the request URL and write the HTTP response.

```swift
final class HLSProxyServer {
    private func handleSegmentRequest(_ url: URL,
                                      connection: NWConnection) async {
        // 1. Check cache (HLSSimpleCache handles key normalisation + lock)
        if let cached = await HLSSimpleCache.shared.data(for: url) {
            respond(with: cached, to: connection)
            return
        }

        // 2. Cache miss — acquire lock, fetch, write, serve
        let key = HLSCacheKeyFactory.cacheKey(for: url)
        await HLSSimpleCache.shared.lock.lock(key)
        defer { Task { await HLSSimpleCache.shared.lock.unlock(key) } }

        // Re-check after acquiring lock (another request may have cached it)
        if let cached = await HLSSimpleCache.shared.data(for: url) {
            respond(with: cached, to: connection)
            return
        }

        // Fetch and simultaneously serve + write (TeeDataSource pattern)
        guard let data = try? await URLSession.shared.data(from: url).0 else {
            respond(statusCode: 502, to: connection); return
        }
        await HLSSimpleCache.shared.store(data, for: url)
        respond(with: data, to: connection)
    }
}
```

---

## Graceful Degradation (FLAG_IGNORE_CACHE_ON_ERROR equivalent)

If the proxy is killed by iOS under memory pressure:
- AVPlayer's pending request to `localhost:PORT` gets a connection refused
- AVPlayer retries — this time the proxy has restarted (it restarts on every
  `+registerWithRegistrar:` call)
- If it hasn't restarted yet, AVPlayer falls back to fetching from R2 directly
  after a timeout

This is equivalent to Media3's `FLAG_IGNORE_CACHE_ON_ERROR`: cache errors
fall through to upstream. AVPlayer handles this correctly for HLS — a failed
segment request triggers a retry, not a playback failure.

The cache index on disk is never lost — `HLSCacheIndex` persists after every
write. Even if the proxy is killed mid-write, the index only includes completed
segments (`isFullyCached: true`). Partial writes are discarded on index reload,
same as Media3's `SimpleCache` behaviour.

---

## Pigeon API (unchanged from original plan)

```dart
// Cache management — exposed to Flutter layer
void setCacheMaxSize(int maxSizeBytes);
void clearCache();
int getCacheSize();
bool isCacheEnabled();
void setCacheEnabled(bool enabled);
```

---

## Implementation Order

| Step | Component | Effort | Notes |
|------|-----------|--------|-------|
| 1 | `HLSCacheKeyFactory` | 1 hour | Pure function, trivial, test first |
| 2 | `HLSCacheSpan` + `HLSCacheIndex` | 1 day | Storage model + persistence |
| 3 | `HLSCacheEvictor` | 0.5 day | LRU logic, unit-testable in isolation |
| 4 | `HLSCacheLock` | 0.5 day | Swift actor, straightforward |
| 5 | `HLSSimpleCache` | 1 day | Wires 1-4 together, integration tests |
| 6 | `HLSProxyServer` | 1 day | NWListener + delegates to HLSSimpleCache |
| 7 | `HLSProxyServerBridge` + plugin hook | 0.5 day | ObjC bridge, 1 line in plugin |

**Total: ~5-6 days**

Steps 1-5 can be developed and tested entirely without AVPlayer or Flutter.
`HLSSimpleCache` is a standalone Swift module — write unit tests for it before
touching any native plugin code.

---

## Key Differences From Original Plan

| Aspect | Original Plan | Updated Plan |
|--------|--------------|--------------|
| Primary complexity | Proxy (monolithic) | Cache storage layer (Media3-inspired) |
| Proxy role | Smart — cache logic inside proxy | Thin — just HTTP plumbing |
| URL normalisation | Manual SHA256 of full URL | `HLSCacheKeyFactory` (R2 signed URL safe) |
| Concurrent request handling | Basic mutex | `HLSCacheLock` actor (FLAG_BLOCK_ON_CACHE) |
| Write-while-serve | Not addressed | Explicit TeeDataSource pattern |
| Index persistence | Rebuilt from disk on launch | Persisted JSON index (StandaloneDatabaseProvider equivalent) |
| Graceful degradation on kill | Not addressed | FLAG_IGNORE_CACHE_ON_ERROR equivalent |
| Testability | Hard (proxy entangled with cache) | Each component independently testable |

---

## What This Does NOT Include (Separate Phase)

- `AVAssetDownloadURLSession` offline downloads — independent feature, separate phase
- ABR quality control API — independent feature, no dependency on cache
- Android `DownloadManager` — independent feature, shares `SimpleCache` instance