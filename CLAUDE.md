# loge

loge: a Stremio-addon client for iPhone/iPad, Apple TV and Mac, in native SwiftUI, public on
GitHub under the PolyForm Noncommercial License 1.0.0 (source-available, no commercial use;
GPL-3.0 until 10 November 2026) and installed by sideloading (SideStore source, no App Store).
The project, scheme, product and `LogeCore` package are all named loge; only the bundle ID
(`li.tjh.MediaApp`), Keychain service names and log subsystem keep the old working name, so
saved data and sign-ins carry over. It browses catalogs from Stremio addons, shows details,
lists streams and plays them with mpv. The look follows the Strand app: charcoal canvas,
artwork-led, white accent, system font, no cards/gradients/badges.

What users get is described in README.md, docs/APP_OVERVIEW.md and ROADMAP.md (shipped
features, proposals, scope). History of individual changes is in git and the PRs.

## Layout

- `project.yml` — XcodeGen spec; the `.xcodeproj` is generated and gitignored. One app target
  (`loge`) builds for iOS, tvOS and macOS; `logeUITests` holds on-demand UI tests.
- `Core/` — `LogeCore` Swift package, no UI, grouped by domain: Addons (protocol client,
  routing in user order, `AddonStore`, `StreamDetails`, `SourceSelection`), Library
  (`LibraryStore`: progress, My List, history, remembered sources), Playback, Discovery,
  TMDB, Trakt (`TraktChange` queue), Sync (`SyncedSettings`), plus `Keychain` and `Accent`.
  All persistence is `UserDefaults` because tvOS can purge app files.
- `App/Browse/` — by screen: Components, Home, Details, Sources, People, Discovery.
- `App/Player/` — `PlaybackSession` (owns the playback in progress, outliving the player
  screen for Picture in Picture), `MPVPlayer` (libmpv, AVFoundation video layer),
  `ScrubPreview` (a second, silent mpv for timeline thumbnails), `PlayerView`, controls and
  menus, `PictureInPicture`, `NowPlaying`, next-episode countdown, tvOS remote swipe reader.
- `App/Settings/` — an index of pages: Sync, addons, Trakt, TMDB, accent; playback
  preferences inline; About (version, build commit, credits) and Data Sources, which holds
  all attribution rather than putting it under artwork.
- `web/` — the project page for loge.tjh.li: static HTML/CSS in tjh.li's design, no scripts
  or build step; screenshots are web-sized copies from `docs/screenshots`. Cloudflare Pages
  (project `loge`), deployed by `.github/workflows/web.yml` when `web/` changes on main.
- `Tools/sync-gateway` — self-hostable account sync (gateway in front of a private CouchDB,
  local admin page); see docs/SYNC.md. Personal infrastructure lives in a separate private repo.
- `Tools/run-device.sh` — Debug build onto the connected iPhone/iPad with the free Personal Team.
- `Tools/install.sh` — Release build of origin/main (own checkout in `.build/install`) onto a
  device chosen from a menu: a reachable iPhone/iPad, the Apple TV via atvloadly, or all.
- `Tools/test-addon.py` — local stream addon at `http://127.0.0.1:8765/manifest.json` with
  test streams (MKV, HEVC, multi-track HLS, header-protected, broken, torrent).
- `Tools/render-icons.swift` — regenerates `App/Assets.xcassets` (icons, top shelf, accent).
  It deletes and rewrites the catalog, so change the script rather than the assets.
- `Vendor/MPVKit/` — MPVKit's LGPL product with a patched `Libmpv.xcframework.zip` that adds
  `vo=avfoundation` (an `AVSampleBufferDisplayLayer`, for Picture in Picture and HDR). Rebuild
  with `rebuild-libmpv.sh`; see its README.
- Mac updates use Sparkle (feed `https://tjh.li/loge/appcast.xml`); signing keys and
  certificates are Actions secrets, see docs/MAC_UPDATES.md.
- `.github/workflows/ci.yml` — pull requests: Core tests and warning-free builds for all three.
- `.github/workflows/release.yml` — each push to main that changes what goes into the builds
  (an allowlist; README, LICENSE, docs, web and tests don't count): Core tests and the three
  platforms, then unsigned iOS/tvOS `.ipa` files and a self-signed Mac `.dmg`
  (`Tools/build-dmg.sh`, not notarized) as release `build-<commit count>`. Run by hand on
  another branch, it builds and signs without publishing.
- `.github/workflows/source.yml` — writes the GitHub Pages site at `https://tjh.li/loge/`
  (SideStore `source.json` via `Tools/sidestore-source.py`, Mac appcast, icon, screenshots from
  `web/images`) from the published releases; called after each release, and run alone when the
  source script or images change.

## Commands

```bash
xcodegen generate                                   # after adding/removing files
(cd Core && swift test)                             # Core unit tests
xcodebuild -project loge.xcodeproj -scheme loge -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode build
# also: 'generic/platform=tvOS Simulator' and 'platform=macOS'
Tools/build-ipa.sh [iOS|tvOS]                       # unsigned .ipa files in .build/ipa
Tools/install-tv.sh                                 # build tvOS, upload to atvloadly for the Apple TV
Tools/run-device.sh [--console|--no-launch]         # build, install, launch on the iPhone/iPad
Tools/install.sh [--here]                           # latest main (or this checkout) on a device picked from a menu
```

Devices normally install from the SideStore source. `run-device.sh` signs with the free
Personal Team in Xcode; the phone needs Developer Mode and the developer trusted once; free
installs expire after 7 days. atvloadly runs on a home-network server (`ATVLOADLY`, default in
`install-tv.sh`) and re-signs nightly 03:00–06:30. A free Apple ID allows 3 sideloaded apps
at once across Xcode, Sideloadly and atvloadly.

On-demand UI tests (need network and installed addons; skipped otherwise):

```bash
TEST_RUNNER_UI_FLOWS=1 TEST_RUNNER_SCREENSHOT_DIR=/tmp/shots xcodebuild test -project loge.xcodeproj -scheme loge -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath .build/xcode -only-testing:logeUITests/FlowTests
```

`UITests/RemoteDriverTests.swift` drives the Apple TV simulator's remote from a command file
(see its header); XCUIRemote can press buttons but not swipe. Each press also stalls the app's
main thread 60–100 ms, so for timing send arrow keys straight to the simulator and sample the
app with macOS `sample <pid>`. The Apple TV is paired with Xcode for `devicectl` and crash
logs; Instruments over the network to it drops after about a second.
`--discovery-ui-test` with `-DISCOVERY_SCREEN recommended|details` shows recommendations offline.

## Conventions

- Before finishing: build all three platforms with no warnings, run Core tests, and check
  UI changes in the simulators (screenshots), including tvOS focus with the remote driver.
  Xcode's AppIntents metadata extraction warning is expected.
- Real-device testing isn't planned (ROADMAP.md): verify in simulators and automated tests,
  don't ask for or schedule hardware checks, and name what a simulator can't establish (HDR,
  display matching, remote swipes, screen lock, physical cross-device handoff) as a limit.
  macOS has no simulator; report Mac runtime behaviour as unverified unless checked.
- Reuse the existing tests and fixtures (`LibraryStoreTests`, `TraktTests`, `FlowTests`,
  `PlaybackRegressionTests`, `RemoteDriverTests`, `Tools/test-addon.py`, the playback
  fixtures) rather than creating another harness.
- Platform differences use `#if os(...)` in place; sizes live in `Metrics`
  (`App/Browse/Components/BrowseComponents.swift`), iPad/landscape via size classes. Phone-only
  behaviour checks the device (`Metrics.isPhone`), not the size class, so a narrow iPad window
  keeps its tabs.
- Expanding sync scope (e.g. Watch Later/lists) or changing visible UI/interaction design
  needs the user's agreement on a concrete proposal first.
- No co-author or "generated with" lines in commits or PRs; commit only when asked.

## Privacy

The user's real stream addon is AIOStreams with Real-Debrid. Its manifest URL embeds their
configuration and keys: never write it to the repo, logs, tests or memory. The app only ever
shows or logs an addon's host. Sync recovery keys, admin tokens and personal infrastructure
stay out of this repo.

## Decisions

Distributed as a SideStore source (each user signs with a free Apple ID; Apple TV via
Sideloadly/atvloadly); no paid developer account. MPVKit player, vendored with an AVFoundation
video output. Addons are added as manifest URLs. Cross-device sync is Trakt (user's own app
keys) or the optional self-hosted account sync, never iCloud or a default hosted server; Trakt
pauses while an account is connected. iPhone/iPad and Apple TV are equal main devices.
Picture in Picture is required; downloads are out of scope; UI is English only for now.
iPhone browsing is portrait-only (`AppDelegate`); the player turns.

## Things that aren't obvious from the code

- Player menus (`SubtitlesMenu`, `AudioMenu`, `MoreMenu`) are `Equatable` and used with
  `.equatable()`: the controls redraw every second for the timeline, and without it open
  menus rebuild and lose their scroll position.
- Turning subtitles on shows a track mpv already demuxes (`sub-visibility`); selecting a new
  embedded track makes mpv re-read its whole buffer and stall.
- Play and Resume never open a saved stream URL (debrid links expire); they wait for the
  fresh list and pick the same file or release from it.
- A skip to the file's end stops 0.2 s short and plays out the rest, or Up Next never starts
  when skipping credits while paused.
- On tvOS the remote surface stands aside while the panel or Up Next has focus; lying under
  their buttons it steals focus from them.
- Festival and genre tiles push by value; a view-built destination left the links inside dead.
- Home's artwork prefetch uses plain data tasks, not a task group (suspected Release crash).
  An optimizer bug once lost a task group's result in Release builds, so test Release too.
- Don't add `minimumScaleFactor` to `IconCaption`; the row then lays the icons out at half size.
- iPad details switch between `DetailColumnsLayout` and a `VStackLayout` under `AnyLayout`,
  so rotating keeps the chosen season and loaded reviews.
- The phone hero shows the portrait poster: a title near the top of a poster reads twice with
  the logo, and that can't be detected.
- The Mac player window is a principal window, since an associated one can't go full screen.
- Search's keyboard reappearing after going back is the system restoring a focused field;
  clearing focus on leaving doesn't stop it.

## Testing gotchas

- Playback UI tests expect the simulator in portrait; one left in landscape fails
  `testEpisodePausePersistsAndResumesAfterRelaunch`.
- `FlowTests.testTrackSwitchingWhilePlaying` is flaky: menus sometimes don't open in time.
- iPhone simulators lack Picture in Picture; use iPad for that path.
- `Test Streams` surviving uninstall on the iPhone 18 Pro simulator is a stale
  `data/Library/Preferences/li.tjh.MediaApp.plist` outside the app container.
- Background-recovery tests check the picture's pixels; an older check couldn't see black video.

## Open

- ROADMAP.md lists the remaining verification item (OS runtime smoke tests) and the proposed
  features; agree on scope before building any of them.
- Cross-device sync: reviewed and fixed; proposed expansions (Watch Later and custom lists)
  await a decision.
- Returning from "All reviews" on tvOS moves focus to Play.
- Top Shelf is on hold: atvloadly installs the extension and its App Group
  (`group.li.tjh.MediaApp.<team ID>`, read from the embedded profile), but tvOS never launches
  it; the reason is only in the Apple TV's live log (branch `claude/top-shelf-test`).
- The tvOS Home lag fix is measured in the simulator only (4K rendering still shows 90–170 ms
  frame gaps per move); keep simulator measurements comparable.
- Unverified: playback and Picture in Picture on tvOS and macOS, HDR output, tvOS display
  matching, swipe-to-scrub and the scrub preview on screen, live Trakt and physical
  phone-to-Apple-TV handoff, Mac sources rows with AIOStreams' long names, the Search genre
  pill and Watch Later row on Apple TV.
