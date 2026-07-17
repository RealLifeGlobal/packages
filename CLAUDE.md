# Repo context: fork of flutter/packages

This is a **fork of `flutter/packages`**. Upstream is tracked by `origin/main`; the
fork's integration branch is **`dev`**. All fork customization lives in
**`packages/video_player/*`** — every other package is upstream and merges cleanly.

The fork adds to `video_player`: background playback (Android `MediaSessionService`
+ foreground service), Picture-in-Picture, HLS caching, ABR / video-quality control,
configurable decoder selection, and web MediaSession/PiP. Design notes live in
`packages/video_player/FORK_PLAN.md` and `packages/video_player/FORK_TECHNICAL_REFERENCE.md`.

Toolchain: **fvm** (`dart` / `flutter` resolve to `~/fvm/default/bin`). Dart 3.12.x.

---

# The recurring task: merging upstream into the fork

`git merge origin/main` (into `dev`) recurs and always conflicts in the same places
because both sides edit the same `video_player` files. Conflicts are predictable —
resolve them with the rules below, **don't reinvent the resolution each time.**

## Playbook

1. `git fetch origin && git merge origin/main` (on `dev`).
2. `git diff --name-only --diff-filter=U` — conflicts will be under `packages/video_player/`.
3. Resolve **source** files by hand using the rules below. Leave generated `*.g.*` for step 4.
4. **Regenerate pigeon** instead of hand-merging generated files (see "Pigeon").
5. `git add packages/video_player/` then verify (see "Verify").
6. Commit the merge, documenting each resolution in the message.

## Resolution rules (the non-obvious decisions)

- **`path:` dependencies always win.** `pubspec.yaml` conflicts pit the fork's
  `video_player_platform_interface: { path: ../video_player_platform_interface }`
  against upstream's `video_player_platform_interface: ^6.x.0`. **Keep the `path:`
  form** — the fork's interface has methods (PiP, cache, ABR, decoder, background
  playback) not in any published version. Accepting `^6.x.0` breaks the build.
  Applies to `video_player_avfoundation/{pubspec,example/pubspec}.yaml` and
  `video_player_web/pubspec.yaml`.

- **Pigeon: union the source, then regenerate.** Never hand-merge
  `*.g.dart` / `*.g.m` / `*.g.h` (dozens of conflict regions, error-prone). Instead:
  - Resolve the **source** `pigeons/*.dart` as a **union** of both sides' classes and
    `@HostApi` methods (fork features + upstream features; they don't collide by name).
  - Regenerate (see command below). This overwrites all three generated outputs.

- **Overlapping features → union (keep both).** When the fork and upstream both add to
  the same API (e.g. fork's ABR `getAvailableQualities`/`setMaxBitrate` vs upstream's
  `getVideoTracks`/`selectVideoTrack`), keep **both** — preserve fork work, take
  upstream's addition. Same for `@override` blocks in `avfoundation_video_player.dart`.
  The native `FVPVideoPlayer.m` and `video_player_platform_interface.dart` usually
  auto-merge with both sets already present — verify, don't assume.

- **Versions: take upstream's (higher) number.** For `version:` conflicts use upstream's
  bump. In `CHANGELOG.md`, fold the fork's unreleased bullets into that version's entry
  (the fork's interim versions were never published).

- **Minimize gratuitous divergence.** For pure comment/formatting conflicts, prefer the
  upstream text. Every fork-only line is a future conflict; keep divergence to actual
  features.

## Pigeon regeneration

```sh
cd packages/video_player/video_player_avfoundation
flutter pub get
dart run pigeon --input pigeons/video_player_instance_messages.dart   # silent = success
```

`ConfigurePigeon` in the source declares all output paths, so no flags are needed.
There are two pigeon inputs here (`video_player_instance_messages.dart`,
`video_player_plugin_messages.dart`); regenerate whichever conflicted.

## Verify before committing

- `dart analyze lib/` in every touched Dart package (`video_player`,
  `_avfoundation`, `_web`, `_platform_interface`). Expect "No issues found!".
- Confirm the native ObjC implements every protocol method the regenerated header
  declares (incomplete protocol = iOS build failure):
  ```sh
  cd packages/video_player/video_player_avfoundation/darwin/.../video_player_avfoundation_objc
  # every selector in VideoPlayerInstanceMessages.g.h must appear in FVPVideoPlayer.m
  ```
- `grep -rn '^<<<<<<<\|^=======$\|^>>>>>>>' packages/video_player/` returns nothing.

---

# Keeping the fork low-maintenance

- **Merge upstream frequently** — small, frequent merges beat large rare ones; the
  conflict surface above is the same size every time but easier when changes are small.
- **Isolate custom code** into new files/methods rather than editing upstream lines,
  so git auto-merges. Generated-file churn is unavoidable but is *regenerated*, not merged.
- **Upstream generic fixes.** Bug fixes that aren't fork-specific (e.g. the iOS
  backgrounding-crash fix) are worth a PR to `flutter/packages`; once merged upstream they
  stop being a fork-only diff and stop conflicting.

---

# Implementing a fork feature: robust, not lazy

Worked cautionary example: our `setPreventsDisplaySleep` (feat/ios-prevents-display-sleep) vs
upstream's `setPreventsDisplaySleepDuringVideoPlayback` (#11225), which shipped the same capability
far more completely. "Lazy" = the thinnest platform-channel passthrough that compiles. "Robust" =
a first-class property of the state model, config surface, and existing idioms — then tested and
documented. Before calling a `video_player` feature done, apply all of these:

- **Put the property in the state model, not just a passthrough.** A new player property must be a
  field on `VideoPlayerValue`, threaded through `copyWith` / `==` / `hashCode` / `toString`.
  If you can't read back what you set, it isn't done. (Ours never touched `value`.)

- **Make it configurable at construction, not runtime-only.** If it's a player setting, add it to
  `VideoPlayerOptions` with a default and **apply it on every data-source creation path**
  (asset / network / file / contentUri) — not only via a later setter. (Ours had no option.)

- **Follow the existing controller idiom exactly.** Mutations are
  `setX(...) { value = value.copyWith(x: ...); await _applyX(); }`, where `_applyX` guards
  `_isDisposedOrNotInitialized` and calls the platform (see `setLooping`, `setVolume`). Don't invent
  a one-off shape. (Ours guarded in the public setter and skipped the value/`_apply` steps.)

- **Match the platform-interface contract; fully model any richer semantic.** Upstream uses a
  non-nullable `bool` with a documented default + a **no-op default impl** for platforms that don't
  support it. A richer semantic is fine *if modeled everywhere*: our `bool?` (`null` = "don't cast
  AVPlayer's vote, defer to the reference-counted `SafeWakelock`") is a real requirement but it lived
  only in the ObjC setter. A tri-state only the native layer understands is the lazy version of a
  good idea — put it in value/options/docs/tests too, or don't add it.

- **Ship the "boring" parts — they are the feature.** Unit test (at least the default value + a
  state round-trip), `CHANGELOG.md` entry, `version:` bump, and dartdoc on every new public member.
  Skipping these is the signature of a lazy change.

- **Align with upstream's name/shape — check before inventing.** This fork merges upstream forever,
  so a parallel, differently-named API for something upstream also implements *guarantees* a future
  duplicate (exactly what `setPreventsDisplaySleep` vs `setPreventsDisplaySleepDuringVideoPlayback`
  now creates on `dev`). Before adding a public API, grep the platform interface and search
  `flutter/packages` issues/PRs; if upstream has or plans it, adopt its name and signature and add
  only the fork-specific delta.
