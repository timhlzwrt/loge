# loge

loge: a Stremio-addon client for iPhone/iPad, Apple TV and Mac, in native SwiftUI, public on
GitHub under GPL-3.0 and installed by sideloading (SideStore source, no App Store). The project, scheme, product and `LogeCore` package are all named loge; only the bundle ID
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
- `App/Player/` — `PlaybackSession` (owns the playback in progress, outliving the player
  screen for Picture in Picture), `MPVPlayer` (libmpv, AVFoundation video layer), `ScrubPreview`
  (a second, silent mpv instance for timeline thumbnails), `PlayerView`,
  controls and menus, `PictureInPicture`, `NowPlaying`, next-episode countdown, tvOS remote
  swipe reader.
- `App/Settings/` — an index of pages: addons (install/reorder/remove), Trakt, TMDB, accent;
  playback preferences inline; About with version, credits and the Data Sources page
  (all attribution lives there rather than under artwork).
- `Tools/run-device.sh` — Debug build onto the connected iPhone/iPad with the free Personal Team.
- `Tools/install.sh` — Release build of origin/main (in the nightly checkout) onto a device
  chosen from a menu: a reachable iPhone/iPad, the Apple TV via atvloadly, or all.
- `Tools/test-addon.py` — local stream addon at `http://127.0.0.1:8765/manifest.json` with
  test streams (MKV, HEVC, multi-track HLS, header-protected, broken, torrent).
- `Tools/render-icons.swift` — regenerates `App/Assets.xcassets` (icons, top shelf, accent);
  the mark is a white "l" with a turned foot on the charcoal canvas.
  It deletes and rewrites the catalog, so change the script rather than the assets.
- `Vendor/MPVKit/` — MPVKit's LGPL product with a patched `Libmpv.xcframework.zip` that adds
  `vo=avfoundation` (an `AVSampleBufferDisplayLayer`, for Picture in Picture and HDR). Rebuild
  with `rebuild-libmpv.sh`; see its README.
- `.github/workflows/ci.yml` — Core tests and warning-free builds for iOS, tvOS and macOS.
- `.github/workflows/release.yml` — every push to main: unsigned iOS and tvOS `.ipa` files as
  release `build-<commit count>`, and the SideStore source (`Tools/sidestore-source.py`) on
  GitHub Pages at `https://timhlzwrt.github.io/loge/source.json`.

## Commands

```bash
xcodegen generate                                   # after adding/removing files
(cd Core && swift test)                             # Core unit tests
xcodebuild -project loge.xcodeproj -scheme loge -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode build
# also: 'generic/platform=tvOS Simulator' and 'platform=macOS'
Tools/build-ipa.sh [iOS|tvOS]                       # unsigned .ipa files in .build/ipa
Tools/install-tv.sh                                 # build tvOS, install on the Apple TV via atvloadly
Tools/run-device.sh [--console|--no-launch]         # build, install, launch on the iPhone/iPad
Tools/install.sh [--here]                           # latest main (or this checkout) on a device picked from a menu
DEVICE=<udid> Tools/nightly-deploy.sh --install     # nightly install of main on both (launchd)
```

`run-device.sh` signs with the free Personal Team signed in to Xcode (Settings > Accounts);
the phone needs Developer Mode on (Settings > Privacy & Security) and the developer trusted
once (Settings > General > VPN & Device Management). Free installs expire after 7 days.

Devices are installed without a paid account. `nightly-deploy.sh` runs at 02:30 from launchd
in its own checkout (`.build/nightly` of the main repo): when origin/main moved it installs a
Release build on the Apple TV via `install-tv.sh` and on the iPhone over Wi-Fi via
`run-device.sh`, and it reinstalls the iPhone after 5 days so the free signature never lapses.
It logs to `~/Library/Logs/loge-nightly.log` and shows a notification when an install fails.
atvloadly runs on a server on the home network (`ATVLOADLY`, default in `install-tv.sh`, set up
in a separate infrastructure repo); it re-signs every night 03:00–06:30, and `install-tv.sh` uploads a
new build to it. A free Apple ID allows 3 sideloaded apps at once across Xcode, Sideloadly and
atvloadly.

On-demand UI tests (need network and installed addons; skipped otherwise):

```bash
TEST_RUNNER_UI_FLOWS=1 TEST_RUNNER_SCREENSHOT_DIR=/tmp/shots xcodebuild test -project loge.xcodeproj -scheme loge -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath .build/xcode -only-testing:logeUITests/FlowTests
```

`UITests/RemoteDriverTests.swift` drives the Apple TV simulator's remote from a command file
(see its header); XCUIRemote can press buttons but not swipe. Each press also stalls the app's
main thread 60–100 ms, so for timing send arrow keys straight to the simulator and sample the
app with macOS `sample <pid>`. The Apple TV is paired with Xcode (Product > Destination >
Manage Devices…) for `devicectl` and crash logs; Instruments over the network to it drops
after about a second.

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
Phase 4 and 2 November: TMDB metadata, filmographies and festival collections (PR #9); both
devices get a Release build of main every night (`nightly-deploy.sh`); sources load in
Release builds again (an optimizer bug lost the task group's result); festival queries take
about a second instead of timing out.
Phase 3: History, every played or marked-watched item by day: a row of stills at the end of
My Lists and a grid per day behind "History ›" (PR #10).
3 November: browsing tvOS Home no longer lags (PR #11). A focus move redrew every row, every
poster in the focused row, and the backdrop crossfade on the CPU; now only the backdrop,
header and the two posters involved update.
3 November, release prep (PR #12): everything named loge except the bundle ID, Keychain
services and log subsystem (`li.tjh.MediaApp`, kept for saved data and sign-ins). Settings is
an index of pages with About (credits: development Tim Holzwarth, testing Lenja) and Data
Sources, which holds all attribution that used to sit under artwork and lists. Details name
their actions (Watch Later, Lists, Sources); a missing playback addon can be added from the
sources sheet; source rows lead with size and HDR; cast without photos reads as credits;
genre tiles show a small still first; Search shows a genre as a removable pill; Watch Later
is one section. Before/after screenshots are in the PR.
3 November, fixes from using it: festival and genre tiles push by value, so winners open
(a view-built destination left the links inside dead); Home's artwork prefetch is plain
data tasks, not a task group (likely cause of a Release crash on the iPhone after opening a
festival); turning subtitles on shows a track mpv already demuxes (`sub-visibility`), since
selecting a new embedded track makes mpv re-read its whole buffer and stall; mpv waits for
5 s of buffer after running dry and the player shows the download speed while buffering;
iPhone browsing is portrait-only (`AppDelegate`), the player turns; the details backdrop
fades as the page scrolls; the player's Close button is a full 44 pt target. Playback measures
the download speed while mpv fills its buffer (`ConnectionSpeed`, per device, loopback ignored),
and the sources list marks the best source within ¾ of it as recommended, without playing it,
whenever some listed source is too much for the connection (`StreamDetails.recommendedIndex`).
Settings > About shows the build's commit, date, branch and a GitHub compare link, stamped into
Info.plist by the "Stamp commit" build phase (`project.yml`), which also sets the build number to
the commit count. The repo went public with a README for outside users; agent handoff notes
and dated review reports were removed. Others install through the SideStore source.
`FlowTests.testTrackSwitchingWhilePlaying` is flaky: menus sometimes don't open in time.

Decisions: public under GPL-3.0, distributed as a SideStore source (each user signs with a free
Apple ID; Apple TV via Sideloadly); MPVKit player (vendored with an AVFoundation video output); addons added as manual
manifest URLs; cross-device sync via Trakt (not iCloud), with the user's own Trakt app keys
entered in Settings; no paid Apple developer account, devices are sideloaded (see Commands).
iPhone/iPad and Apple TV are equal main devices, so no platform gets priority. Picture in
Picture is required; downloads are out of scope; UI is English only for now.

Next, in plan order:

1. Phase 2 leftovers: tvOS swipe-to-scrub and Mac playback need checking by hand.
2. tvOS Top Shelf with Continue Watching, on hold. Tested 2 November (branch
   `claude/top-shelf-test`): atvloadly signs and installs a Top Shelf extension with a free
   Apple ID and registers the App Group (`group.li.tjh.MediaApp.<team ID>`; the real name has
   to be read from the embedded provisioning profile), but tvOS never launches the extension:
   no process, no crash log, the shelf stays empty. The reason is only in the Apple TV's live
   log (Console.app with the paired device); read it before building more.
3. Check the Home lag fix on the Apple TV itself (simulator only so far; simulator 4K
   rendering still shows 90–170 ms frame gaps per move).

Open from the 2 November list (the rest shipped in PR #9):

- Check on real devices: the Close button always closes, intro/recap/credits skip offers
  seek correctly (tvOS focus too), and English is picked as the default audio. Sources and
  playback with AIOStreams and the advancing timeline are confirmed (simulator and iPhone);
  close and recap/intro skips passed simulator UI tests.
- Embedded TMDB member reviews, popularity-ranked directors, person role filters and dated
  2026 festival editions shipped in PR #13.

Untested so far: Mac playback and sources rows with AIOStreams' long
names; on Apple TV the Search genre pill and the Watch Later row. Playback and Picture in Picture on tvOS and macOS, HDR output and tvOS display
matching (need real hardware), Trakt against the live API, tvOS swipe-to-scrub and the scrub preview on screen. iPhone simulators report Picture in Picture as unsupported; the isolated iPad PiP restoration check passed in the 3 November follow-up.

3 November follow-up: the Mac Search, title details and member reviews were inspected
in the native app. An isolated iPhone playback test passed advancing time, English audio
selection with German first in the file, all three timed skips, close/reopen and source
replacement. These are simulator results with synthetic timing segments, not real-device
chapter or HDR verification. Physical iPhone tests stopped before installation because
Xcode has no signed-in developer account/profile for the UI-test runner. Top Shelf log
collection requires administrator access; no further extension build was attempted.

After the user configured Xcode signing and approved the Mac Keychain prompt, native
Mac checks passed Settings/Data Sources, live review previews/full text, director
artwork, festival filtering and winner-seeded Search. Both isolated playback tests
then passed on the physical iPhone (timeline, audio, three synthetic skips,
close/reopen, source replacement and PiP restoration). Evidence:
`/tmp/loge-iphone-hardware-connected.xcresult`. Top Shelf and the remaining Apple TV
hardware/HDR/Trakt checks are still pending; no extension build was attempted.
