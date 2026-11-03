# loge

## Active checkout and preflight

The user confirmed on 2026-11-02 that the current app work belongs in
`/Users/tjh/Developer/MediaApp/.claude/worktrees/todo-batch`.
The handoff branch is `codex/tmdb-discovery-handoff`, based on current `main`
(which includes `claude/todo-batch` at `4243d49`).
The top-level checkout was an older base and must not be used for app edits or builds.
Before editing, after resuming, and before building/installing: run `Tools/check-checkout.sh`
(it must succeed), then run `pwd`,
`git status --short --branch`, `git worktree list`, and compare recent commits in
candidate checkouts. Use the user-confirmed checkout and explicit working directories.
Do not assume the current directory, branch name, or a newer timestamp proves which
version is current. Preserve dirty work and resolve version mismatches before editing.
Never replace a newer feature or persistence format with an older implementation.
See `.cursor/rules/checkout-preflight.mdc`.

loge: a private, never-published Stremio-addon client for iPhone/iPad, Apple TV and Mac,
in native SwiftUI. The project, scheme, product and `LogeCore` package are all named loge; only the bundle ID
(`li.tjh.MediaApp`), Keychain service names and log subsystem keep the old working name, so
saved data and sign-ins carry over. It browses catalogs from Stremio addons, shows details, lists streams and
plays them with mpv. The look follows the Strand app: charcoal canvas, artwork-led, white
accent, system font, no cards/gradients/badges.

## Layout

- `project.yml` — XcodeGen spec; the `.xcodeproj` is generated and gitignored. One app target
  (`loge`) builds for iOS, tvOS and macOS; `logeUITests` holds on-demand UI tests.
- `Core/` — `LogeCore` Swift package, no UI: addon protocol client and models, routing
  (which addon serves catalogs/meta/streams, in user order), `AddonStore` (installed
  addons), `LibraryStore` (watch progress, My List, remembered sources), language codes.
  All persistence is `UserDefaults` because tvOS can purge app files.
- `App/Browse/` — Home (featured carousel on iOS/Mac, focus-driven backdrop header on tvOS),
  catalog rows and See All grid, details (seasons, episodes, Up Next, watched marking),
  sources list (autoplays the remembered or same-binge-group stream), search.
- `App/Player/` — `MPVPlayer` (libmpv via MPVKit, Metal layer), `PlayerView`, controls and
  menus, next-episode countdown, tvOS remote swipe reader.
- `App/Settings/` — an index of pages: addons (install/reorder/remove), Trakt, TMDB, accent;
  playback preferences inline; About with version, credits and the Data Sources page
  (all attribution lives there rather than under artwork).
- `Tools/test-addon.py` — local stream addon at `http://127.0.0.1:8765/manifest.json` with
  test streams (MKV, HEVC, multi-track HLS, header-protected, broken, torrent).
- `Tools/render-icons.swift` — regenerates `App/Assets.xcassets` (icons, top shelf, accent);
  the mark is a white "l" with a turned foot on the charcoal canvas.
  It deletes and rewrites the catalog, so change the script rather than the assets.
- `Vendor/MPVKit/` — MPVKit's LGPL product with a patched `Libmpv.xcframework.zip` so mpv
  follows layer resizes (rotation, window resize). Rebuild with `rebuild-libmpv.sh`; see its README.
- `.github/workflows/ci.yml` — Core tests and warning-free builds for iOS, tvOS and macOS.

## Commands

```bash
xcodegen generate                                   # after adding/removing files
(cd Core && swift test)                             # Core unit tests
xcodebuild -project loge.xcodeproj -scheme loge -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode build
# also: 'generic/platform=tvOS Simulator' and 'platform=macOS'
```

On-demand UI tests (need network and installed addons; skipped otherwise):

```bash
TEST_RUNNER_UI_FLOWS=1 TEST_RUNNER_SCREENSHOT_DIR=/tmp/shots xcodebuild test -project loge.xcodeproj -scheme loge -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath .build/xcode -only-testing:logeUITests/FlowTests
```

`UITests/RemoteDriverTests.swift` drives the Apple TV simulator's remote from a command file
(see its header); XCUIRemote can press buttons but not swipe.

## Conventions

- Before finishing: build all three platforms with no warnings, run Core tests, and check
  UI changes in the simulators (screenshots), including tvOS focus with the remote driver.
- Platform differences use `#if os(...)` in place; sizes live in `Metrics`
  (`App/Browse/BrowseComponents.swift`), iPad/landscape via size classes.
- Commit messages end with a `Co-Authored-By` line; commit only when asked.

## Privacy

The user's real stream addon is AIOStreams with Real-Debrid. Its manifest URL embeds their
configuration and keys: never write it to the repo, logs, tests or memory. The app only ever
shows or logs an addon's host.

## Status

Updated 2 November 2026. Read `docs/HANDOFF.md` before continuing this batch.

Done: existing curated catalogs, Letterboxd shelf, genres/search/sort/year filters,
accent settings, artwork cache/repair, and custom-list persistence are preserved.
Added TMDB secure setup, richer title facts, bounded metadata caches/preloads,
full actor/director movie+TV credits, seven festival-logo collections, Watch Later
and long-press list membership, direct-source-only playback, timeline/close fixes,
and data-dependent intro/recap/credits skip offers.

Verified: 170 Core tests including an opt-in live TMDB check; iPhone/iPad UI flows
and credited-title navigation; Apple TV person-page focus; all three Debug builds
with Swift warnings treated as errors. Xcode emits its known AppIntents extraction
notice. No new build was installed on the user's physical devices.

Remaining: real-device playback regressions, embedded reviews (currently links),
and fuller festival award coverage (currently recorded Wikidata prizes). Trakt is
implemented but requires the user's registered app credentials to connect. See the
handoff for exact limitations, verification commands, and credential handling.
