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
- `App/Settings/` — an index of pages: Sync, addons (install/reorder/remove), Trakt, TMDB, accent;
  playback preferences inline; About with version, credits and the Data Sources page
  (all attribution lives there rather than under artwork).
- `web/` — the project page for loge.tjh.li: static HTML/CSS in tjh.li's type and neutrals, no
  scripts or build step; screenshots are web-sized copies from `docs/screenshots`. Hosted on
  Cloudflare Pages (project `loge`); `.github/workflows/web.yml` deploys it when `web/` changes on main.
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
- `.github/workflows/release.yml` — every push to main: unsigned iOS and tvOS `.ipa` files and a
  self-signed Mac `.dmg` (`Tools/build-dmg.sh`; not notarized, so Gatekeeper needs "Open
  Anyway" once) as release `build-<commit count>`, and the SideStore source (`Tools/sidestore-source.py`) on
  GitHub Pages at `https://tjh.li/loge/source.json` (the account's custom Pages domain).

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
- Real-device testing isn't planned (maintainer's time; ROADMAP.md): verify in simulators
  and automated tests, don't ask for or schedule hardware checks, and name what a
  simulator can't establish (HDR, display matching, remote swipes, screen lock) as a limit.
- Platform differences use `#if os(...)` in place; sizes live in `Metrics`
  (`App/Browse/Components/BrowseComponents.swift`), iPad/landscape via size classes.
- No co-author or "generated with" lines in commits or PRs; commit only when asked.

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

Hardware-only checks in the notes below (swipe-to-scrub, HDR, display matching, physical
handoff, Top Shelf logs) stay unverified limits since the 7 November testing-scope decision.

1. Simulator and automated-test priorities, then the proposed features, as in ROADMAP.md.
2. tvOS Top Shelf with Continue Watching, not planned. Tested 2 November (branch
   `claude/top-shelf-test`): atvloadly signs and installs a Top Shelf extension with a free
   Apple ID and registers the App Group (`group.li.tjh.MediaApp.<team ID>`; the real name has
   to be read from the embedded provisioning profile), but tvOS never launches the extension:
   no process, no crash log, the shelf stays empty. The reason is only in the Apple TV's live
   log (Console.app with the paired device), which is hardware-only.
3. The Home lag fix is measured in the simulator only (4K rendering still shows 90–170 ms
   frame gaps per move); keep simulator measurements comparable.

Todo added 4 November 2026 (implementation status updated below):

- [x] Fix Continue Watching for shows: episode progress does not save correctly.
  Reproduce saving, closing/relaunching, resuming the same episode, and advancing to
  the next episode; verify the saved episode, position and Up Next agree.
- [ ] Fix cross-device Continue Watching and review cross-device sync generally.
  Use the existing Trakt integration; check progress, watched history and lists,
  identify what currently syncs, and propose any expansion of scope before building.
  Cover newer local versus remote progress, offline changes, reconnect and sign-out;
  confirm handoff in both directions between devices with the same Trakt account.
  (8 November: reviewed and bugs fixed, see below; proposed expansions await a decision.)
- [x] Fix black video after turning the screen off and back on during playback.
  (8 November: no failure reproduces in simulators; real screen-off stays a named limit.)
  Reproduce lock/unlock and background/foreground transitions with the existing
  playback fixture; verify visible video returns, the timeline advances, controls
  work and audio stays in sync. Confirm actual screen-off recovery on hardware.
- [x] Smoother user experience, navigation/focus first pass: present concrete ideas and tradeoffs to the user
  before building. Review browse-to-play steps, resume behavior, loading/error
  feedback and returning from playback; agree on changes before implementation.
- [x] Smoother user interface, navigation/focus first pass: present concrete ideas and tradeoffs to the user
  before building. Inspect scrolling, navigation transitions, artwork loading and
  tvOS focus; measure stutters and preserve the existing artwork-led visual style.
- [x] Improve GitHub discoverability ("SEO") and expand the project page. Review
  the repository description/topics and README for clear searchable wording,
  platform screenshots, installation guidance, addon setup, feature explanations,
  troubleshooting and honest limitations. Check any GitHub Pages landing content
  separately from the existing SideStore source feed.

4 November implementation: progress saves on pause, background and playback end;
remote percentage resumes wait for the actual file duration and keep their saved
position until the seek takes effect. Trakt refreshes on foreground, shares token
refresh requests, rejects results after sign-out and imports completed plays to
clear stale Continue Watching entries without overwriting newer rewatches. Stops
use the same 92% completion threshold locally and remotely; explicit Next completes
the episode. Video output resets after backgrounding, including PiP sessions.
The iPhone playback regressions, iPad background/PiP restoration and tvOS library
focus navigation passed. Core: 201 tests passed; all three platform builds passed
with Swift warnings treated as errors (Xcode still emits its AppIntents metadata
extraction warning). Native Mac library layout and simulator screenshots inspected.
The fresh-install browse flow passed after updating stale test labels.

The user chose navigation/scroll/focus smoothness before other UX/UI work. The first
pass reuses per-item focus reporting in Continue Watching and Watch Later; the same
simulator remote sequence reduced row body evaluations from 13 to 2 and 10 to 1,
respectively. This measures view work, not hardware frame rate. Further visual or
interaction changes still need ideas reviewed first. GitHub description/topics
are updated; the expanded README includes setup, sync limits, troubleshooting and
a fresh-install iPhone screenshot.

The user confirmed the playback fixes work on iPhone. Live two-device Trakt
handoff and Apple TV hardware checks remain open. Addon/settings sync is now
implemented as opt-in Settings > Sync with a user-entered HTTPS endpoint and no
default server. The user approved a self-hosted CouchDB design after infrastructure
review: AES-GCM encrypted configuration, device-local Keychain credentials/recovery
key, encrypted persisted baseline, revision-checked writes, automatic foreground
pull/debounced edits, and explicit conflicts preserving independent changes.
Share ordered addon URLs, audio/subtitle preferences, subtitle size, automatic
source size limit and accent. Keep account tokens, remembered stream URLs and
connection measurements local. Public self-hosting files live under
Tools/sync-gateway and docs/SYNC.md; personal infrastructure
and credentials remain outside this public repo. The backend was deployed from
the separate private infrastructure checkout.

Verification: final Core suite reported 219 tests, with both live HTTPS sync tests
passing (encrypted protocol and two independent account stores exchanging addon
order/removal and preferences both ways); two unrelated opt-in provider tests were
skipped. All three final platform builds passed with Swift warnings as errors;
only the existing AppIntents metadata extraction warning remains. iPhone and iPad
Settings opt-in flows passed; native Mac settings inspected; tvOS remote navigation
and key generation passed with screenshots. Backend authentication, route/query
restrictions, concurrent writes, restart and directory backup/restore passed.
These are independent-store live integration and simulator results, not a physical
phone-to-Apple-TV sync handoff. Full Proxmox guest restoration was not tested.


Next sync expansion requested after the initial release:
- [x] Carry playback progress, completion and explicit progress removals through the
  self-hosted service, with offline merge and no competing Trakt import authority.
- [x] Multiple separate accounts in one database, with private playback per person
  and opt-in shared addon groups. Database membership alone is not document-level
  read isolation: put authorization in a gateway and keep CouchDB private.
- [x] Distinguish adding one's own device from inviting another person. Generate
  new scoped sharing codes in the app; default to addons only, allow deliberate
  settings-category sharing, and never include private progress keys in addon invites.
- [x] Local administration UI for account creation/disablement, invite/device
  revocation and service state; leave decrypted user data and recovery keys out.
- [x] Redesign Sync and Settings first: simpler connection flow, visible account
  and sharing status, shorter copy and restrained rounded grouping. Present the
  concrete interaction/visual direction before implementing these UI changes.

Implementation verified: multi-account gateway and local administration are deployed
with legacy /configuration preserved (since removed, see below). Account keys and shared-category keys are
separate; invitations expire after 24 hours and work once. Pending initial imports
and conflicts survive relaunch; profile changes preserve local libraries and
restore the previous local addon setup. Trakt is paused while using an account.
Core: 247-test suite passed (opt-in live tests skipped in the full run); the v2
live two-account test passed separately using disposable accounts. Gateway: ten
tests passed. iPhone/iPad connected sharing controls and tvOS remote navigation
passed; native Mac grouped settings inspected. All three platform builds passed
with Swift warnings treated as errors (existing AppIntents metadata warning only).
Expanded directory backup/restore and production restart passed. Actual physical
iPhone-to-Apple-TV handoff and full Proxmox guest restoration remain unverified.
Production admin token stayed server-side; unlocked GUI interactions were tested
with disposable local data after automatic approval review rejected token export.
Personal enrollment was retained; verification accounts/devices were disabled.
No commits/pushes have been made for this expansion.

7 November, code-health pass (desloppify): the single-user endpoint sync (v1:
`ConfigurationSyncAccount`, `Tools/configuration-sync`, Settings > Previous sync connection)
is removed at the user's request; launch deletes its Keychain login. Account sync is the only
sync: `SyncedSettings` and `SyncError` replace the v1 types, `Accent` and the synced settings
keys live in Core, `Tools/sync-gateway` sets up its own CouchDB with the gateway as the only
database member, and one throwing `Keychain` helper serves Trakt, TMDB and sync. Core sources
and tests are grouped by domain (Addons, Sync, TMDB, Trakt, Discovery, Playback) and App/Browse
by screen (Components, Home, Details, Sources, People, Discovery); `.swiftlint.yml` files record
the lint conventions. `SourceSelection` (Core) holds source grouping, remembered-source and
fallback choice; a shared contract file checks the app client and the gateway against each other.
7 November, recommendations (PR #21): the TMDB details request appends `recommendations,similar`
for More Like This (tiles open through `TMDBTitleView`); `Recommendations` (Core) ranks TMDB
suggestions for up to 8 watched and 4 Watch Later titles on the device for Home's Recommended
row, leaving out anything watched, started, saved or listed. Both hide without a TMDB token.
`--discovery-ui-test` with `-DISCOVERY_SCREEN recommended|details` shows them offline.
8 November, UI fixes: Continue Watching and History share `WatchCard` (caption, title, episode
always visible, including on tvOS). Logos with dark lettering draw white (`LogoTone`); the wide
Home hero keeps the top of its image; the Mac sidebar uses `CatalogSource.shortTitle` and details
name themselves in the toolbar; tvOS can reach Information without TMDB, its Home header looks up
what library entries lack, and My Lists has a left-aligned title; Up Next clears the iOS timeline.
8 November, Home and Search: the phone hero shows the portrait poster (a poster with its title
near the top reads twice with the logo; it can't be detected); wide heroes have the page dots
under the text. Home rows move titles leading an earlier row from the same addon behind their
first eight (`DiscoveryCatalogs.varyingLeads`), so Letterboxd isn't compared; See All keeps rank
order. Search uses the image tiles on every platform, tvOS included, and they still filter in place.
8 November, details: the page runs Episodes, Cast, More Like This, Reviews, Information. Two reviews
show, the rest behind "All reviews". One TMDB prompt, at the foot of the page, only where connecting
would change it. Apple TV hides Reviews without TMDB, since it can't open the links, and types the
addresses out only beside reviews. Open: returning from "All reviews" on tvOS moves focus to Play.
8 November, iPhone navigation: tabs are Home, My Lists and Search; a gear over Home's hero pushes
Settings and scrolls away with it. Title pages (details, sources, people, reviews) hide the tab
bar via `hidingPhoneTabBar()`. Details icons are captioned on iPhone and iPad (`IconCaption`); don't
add `minimumScaleFactor` there, since the row then lays them out at half size. A menu's glass circle
centres on a caption inside its label, so on iPad "Lists" sits below the menu. Checks use the device
(`Metrics.isPhone`), not the size class, so a narrow iPad window keeps its tabs.
8 November, Mac full screen: the player window is a principal window, since an associated one can't
go full screen, and neither launches nor restores by itself. In full screen the main window's
toolbar appears on hover (back button included), so artwork reaches the top; the strip left on
notched screens is the system's.
8 November, iPad layout: a wide landscape page (at least 880 pt and wider than tall, measured on
the page, so the sidebar and window size count) puts details in two columns through
`DetailColumnsLayout`: hero, Episodes and Reviews left, Cast and Information right, More Like This
and the TMDB prompt full width below. It swaps with a `VStackLayout` under `AnyLayout`, so rotating
keeps the chosen season and loaded reviews. `Font.synopsis` is body size on iPad (the device, not the
window); `readingWidth()` caps reviews, biographies and overviews at 640 pt on iOS.
8 November, follow-ups: the Mac cursor hides with the player's controls through
`NSCursor.setHiddenUntilMouseMoves`, so it can't stay hidden, and moving the mouse brings back both.
The details backdrop flattens before it fades (`compositingGroup`), which removes the hard edge.
Reviews keep their state on returning from a pushed page, so tvOS focus stays on the link opened.
Search's keyboard returning after going back is the system restoring a focused field: it isn't
from the iPhone tab bar change, happens only if the keyboard was up when the result was opened,
and clearing `searchFocused` on leaving doesn't stop it. Retry on Sources passed on iPhone.
Play and Resume no longer open a saved stream URL: they wait for the fresh list and play the same
file or release from it, or stay on the list. ElfHosted refused an old link with its own error.

8 November, player, sync and tests: on tvOS, up moves focus to a skip offer (it sits on the
surface, so the focus engine can't reach it) and focus shows on unselected tracks. Sync fixes:
removed titles stay removed while Trakt lists older paused progress (`mergeRemote` checks
removal dates); progress saved during an upload isn't a conflict; artwork filled on one device
survives merging; a marked-watched placeholder duration of 1 isn't used for Trakt progress; a
token Trakt rejects (401) signs out; pause and stop aren't scrobbled below `recordsProgress`.
Background recovery now checks the picture's pixels; a negative control showed the older test
couldn't see a black picture. iPhone simulators lack Picture in Picture, so iPad exercises the
path that keeps playing.

9 November, player and Trakt sweep. Player: on tvOS a skip offer takes focus as it appears, so Select
skips; left, right and down still seek and open the panel from it. Up Next's buttons are reachable with up
(focused by themselves at the end, where Select has nothing else to do). The remote surface stands aside
while the panel or Up Next has focus, because lying under their buttons it beat the buttons beside the
focused one; the same fix makes Info's column reachable. The panel fits its content and lists Sources. The
sources sheet, `PlaybackSession.choosingSource`, now serves all platforms: the Mac has it in More and the
Playback menu. Audio keeps tracks and timing; Speed and Playback Info moved to a new More menu, with
`.menuOrder(.fixed)` and timing above long track lists.
Zoom is a button on iPhone and Mac. Failures explain themselves and offer Try Again (`PlaybackSession.retry`).
Picture in Picture that opened by itself on leaving closes on return to the full-screen player; one opened
with the button stays. The Mac shows the title in full screen, changes the full-screen icon and toggles on
double-click (built, not run here). Trakt: `TraktChange` is a saved queue, sent on reconnect, foreground and
leaving (a background task); old positions lose to newer ones on Trakt, late finished plays go to history with
their real time, removals `DELETE /sync/playback/{id}`. Progress Trakt listed and has since dropped is removed
on other devices unless played here since, queued, or playing per `/users/me/watching`. `scrobble/start` does
clear paused progress (official docs), so `start` now waits for `recordsProgress` like pause and stop, and the
position is queued every 10 s in case the app is killed before the pause. Account sync: same-title progress
takes the newest; removed-versus-played still asks. Packaged build 127 and both feeds advertise 26.0.
`Test Streams` surviving uninstall on the iPhone 18 Pro simulator is a stale
`data/Library/Preferences/li.tjh.MediaApp.plist` outside the app container (3 November): a fresh install reads it.
9 November, iPhone and iPad player like the TV app: close and Picture in Picture/AirPlay (screen icon) at the
top, transport on glass circles in the middle, series over episode at the bottom left with the menus beside it
(on its own row on a portrait iPhone), and an inline timeline under them: a bar without a knob that thickens
under the finger and moves by how far it's dragged, so touching it never skips. The picture dims evenly while
the controls show. Skip offers sit bottom right above the menus; Up Next is in the top right corner, since at
the bottom it covered the play button on a landscape phone. tvOS and the Mac are unchanged.

Verification for these tasks: reuse `LibraryStoreTests`, `TraktTests`,
`UITests/FlowTests.swift`, `UITests/PlaybackRegressionTests.swift`,
`Tools/test-addon.py` and the existing playback fixtures as appropriate; extend
these flows for meaningful regressions rather than creating a separate harness.
Use Xcode's built-in iPhone/iPad and Apple TV simulators, retain screenshots, and
check tvOS focus with `UITests/RemoteDriverTests.swift`; inspect macOS in the native
app. For app changes, run Core tests and warning-free builds for all three
platforms. Report simulator results separately from live Trakt, cross-device and
hardware-only checks; do not mark untested behavior as verified. Use subagents
when there are useful independent investigations or verification tasks.

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
