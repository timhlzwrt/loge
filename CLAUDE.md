# MediaApp

A private, never-published Stremio-addon client for iPhone/iPad, Apple TV and Mac, in
native SwiftUI. It browses catalogs from Stremio addons, shows details, lists streams and
plays them with mpv. The look follows the Strand app: charcoal canvas, artwork-led, white
accent, system font, no cards/gradients/badges.

## Layout

- `project.yml` — XcodeGen spec; the `.xcodeproj` is generated and gitignored. One app target
  (`MediaApp`) builds for iOS, tvOS and macOS; `MediaAppUITests` holds on-demand UI tests.
- `Core/` — `MediaCore` Swift package, no UI: addon protocol client and models, routing
  (which addon serves catalogs/meta/streams, in user order), `AddonStore` (installed
  addons), `LibraryStore` (watch progress, My List, remembered sources), language codes.
  All persistence is `UserDefaults` because tvOS can purge app files.
- `App/Browse/` — Home (featured carousel on iOS/Mac, focus-driven backdrop header on tvOS),
  catalog rows and See All grid, details (seasons, episodes, Up Next, watched marking),
  sources list (autoplays the remembered or same-binge-group stream), search.
- `App/Player/` — `MPVPlayer` (libmpv via MPVKit, Metal layer), `PlayerView`, controls and
  menus, next-episode countdown, tvOS remote swipe reader.
- `App/Settings/` — addons (install/reorder/remove) and playback language preferences.
- `Tools/test-addon.py` — local stream addon at `http://127.0.0.1:8765/manifest.json` with
  test streams (MKV, HEVC, multi-track HLS, header-protected, broken, torrent).
- `Tools/render-icons.swift` — regenerates `App/Assets.xcassets` (icons, top shelf, accent).
  It deletes and rewrites the catalog, so change the script rather than the assets.

## Commands

```bash
xcodegen generate                                   # after adding/removing files
(cd Core && swift test)                             # Core unit tests
xcodebuild -project MediaApp.xcodeproj -scheme MediaApp -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode build
# also: 'generic/platform=tvOS Simulator' and 'platform=macOS'
```

On-demand UI tests (need network and installed addons; skipped otherwise):

```bash
TEST_RUNNER_UI_FLOWS=1 TEST_RUNNER_SCREENSHOT_DIR=/tmp/shots xcodebuild test -project MediaApp.xcodeproj -scheme MediaApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath .build/xcode -only-testing:MediaAppUITests/FlowTests
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

Done: addon client, settings, browse UI, sources and player, tvOS polish, library
(resume, Continue Watching, My List, watched marking, Up Next), autoplay and next-episode,
See All grid with genres, search with recents, app icons, iPad/landscape/Mac layouts.

Decisions: MPVKit player; addons added as manual manifest URLs; cross-device sync via Trakt
(not iCloud); no paid Apple developer account yet, so device installs expire after 7 days.

Next, in plan order: Trakt sync (device-code login, scrobbling, pull playback progress; the
user must register a Trakt API app and supply its Client ID), then installing on real devices.
Untested so far: tvOS swipe-to-scrub, subtitle size during playback, Mac screens beyond Home.
