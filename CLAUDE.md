# MediaApp

Loge: a private, never-published Stremio-addon client for iPhone/iPad, Apple TV and Mac,
in native SwiftUI. The project, scheme and bundle ID keep the working name `MediaApp`; only
the product name is Loge, so saved data carries over. It browses catalogs from Stremio addons, shows details, lists streams and
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
- `App/Player/` — `PlaybackSession` (owns the playback in progress, outliving the player
  screen for Picture in Picture), `MPVPlayer` (libmpv, AVFoundation video layer), `ScrubPreview`
  (a second, silent mpv instance for timeline thumbnails), `PlayerView`,
  controls and menus, `PictureInPicture`, `NowPlaying`, next-episode countdown, tvOS remote
  swipe reader.
- `App/Settings/` — addons (install/reorder/remove) and playback language preferences.
- `Tools/run-device.sh` — Debug build onto the connected iPhone/iPad with the free Personal Team.
- `Tools/test-addon.py` — local stream addon at `http://127.0.0.1:8765/manifest.json` with
  test streams (MKV, HEVC, multi-track HLS, header-protected, broken, torrent).
- `Tools/render-icons.swift` — regenerates `App/Assets.xcassets` (icons, top shelf, accent);
  the mark is a white "l" with a turned foot on the charcoal canvas.
  It deletes and rewrites the catalog, so change the script rather than the assets.
- `Vendor/MPVKit/` — MPVKit's LGPL product with a patched `Libmpv.xcframework.zip` that adds
  `vo=avfoundation` (an `AVSampleBufferDisplayLayer`, for Picture in Picture and HDR). Rebuild
  with `rebuild-libmpv.sh`; see its README.
- `.github/workflows/ci.yml` — Core tests and warning-free builds for iOS, tvOS and macOS.

## Commands

```bash
xcodegen generate                                   # after adding/removing files
(cd Core && swift test)                             # Core unit tests
xcodebuild -project MediaApp.xcodeproj -scheme MediaApp -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode build
# also: 'generic/platform=tvOS Simulator' and 'platform=macOS'
Tools/build-ipa.sh [iOS|tvOS]                       # unsigned .ipa files in .build/ipa
Tools/install-tv.sh                                 # build tvOS, install on the Apple TV via atvloadly
Tools/run-device.sh [--console]                     # build, install, launch on the USB iPhone/iPad
```

`run-device.sh` signs with the free Personal Team signed in to Xcode (Settings > Accounts);
the phone needs Developer Mode on (Settings > Privacy & Security) and the developer trusted
once (Settings > General > VPN & Device Management). Free installs expire after 7 days.

Devices are installed without a paid account: Sideloadly (iPhone/iPad) and atvloadly
(Apple TV) sign the `.ipa` files with a free Apple ID and refresh them before the 7 days run out.
atvloadly runs on the home Proxmox server (CT 107, `http://192.168.178.115:5533`, set up in the
separate infrastructure repo); it re-signs every night 03:00–06:30, and `install-tv.sh` uploads a
new build to it. A free Apple ID allows 3 sideloaded apps at once across Xcode, Sideloadly and
atvloadly.

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
Phase 1: `vo=avfoundation` video output, Picture in Picture (button, automatic on Home,
restore, next episode while floating), Now Playing and remote commands, subtitles from
subtitle addons and streams with timing adjustment, automatic fallback to another source,
tvOS frame-rate and dynamic-range matching, Trakt sign-in, scrobbling and progress sync.
Phase 2: sources list read into quality, HDR, codec, audio and size (`StreamDetails`) with a
best-quality order, retry for unreachable addons, director and cast on details, the Mac's
Playback menu, VoiceOver labels in the player. From using it: Picture in Picture no longer
starts after the player closed, search uses only the built-in catalogs, scrub thumbnails and
keyframe seeks, stream lists fetched while details are open and kept 10 minutes, Cast & Crew
and Information on details with person pages (a Cinemeta name search; no people database).

Decisions: MPVKit player (vendored with an AVFoundation video output); addons added as manual
manifest URLs; cross-device sync via Trakt (not iCloud), with the user's own Trakt app keys
entered in Settings; no paid Apple developer account, devices are sideloaded (see Commands).
iPhone/iPad and Apple TV are equal main devices, so no platform gets priority. Picture in
Picture is required; downloads are out of scope; UI is English only for now.

Next, in plan order:

1. Phase 2 leftovers: tvOS Top Shelf with Continue Watching needs an App Group shared with an
   extension, which free (personal team) signing likely doesn't allow; confirm before building.
   tvOS swipe-to-scrub and Mac screens beyond Home need checking by hand.
2. Phase 3: watch history screen.
3. Phase 4, onto devices: fix the iPhone Release orientation warning, then sideload.

From using it (2026-11-01):

- Player: lag while subtitles are on screen in HDR (maybe all playback); subtitles over HDR
  make the picture look oversharpened (render them separately?); the audio timing menu
  doesn't close.
- Library: Continue Watching sometimes has no image; My List shows have no pictures; split
  the watchlist into shows and movies automatically, plus custom lists.
- Home: remove the "For You" heading; preload covers; better curated covers; add Letterboxd
  popular and genre tiles (popular now and best of all time per genre).
- Search: genre search and filtering.
- Speed: faster first launch and loading in general; overall performance.
- Settings: a customizable accent color instead of only white.
- Picture in Picture subtitles: subtitles now draw in a layer over the video
  (`avfoundation-composite-osd=no`) to stop the HDR lag and processing, so PiP shows none.
  Bring them back with a libmpv patch that composites subtitles only for the PiP window.
- Bitrate: sources rows show no bitrate because addons rarely report one; estimate it from
  size and runtime, and allow sorting by bitrate combined with the other orders.

Untested so far: playback and Picture in Picture on tvOS and macOS, HDR output and tvOS display
matching (need real hardware), Trakt against the live API, tvOS swipe-to-scrub, Mac screens
beyond Home, the scrub preview on screen. iPhone simulators report Picture in Picture as unsupported; use an iPad simulator.
