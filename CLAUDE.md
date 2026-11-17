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
  routing in user order, `AddonStore`, `StreamDetails`, `SourceSelection`, `SetupCode`), Library
  (`LibraryStore`: progress, My List, history, Recently Watched, remembered sources; `EpisodeSchedule`: new
  episodes of the series being watched), Playback, Discovery (`HomeLayout`: Home's shelves), TMDB, Sync (`SyncedSettings`), plus `Keychain`.
  All persistence is `UserDefaults` because tvOS can purge app files.
- `App/Browse/` — by screen: Components, Home, Details, Sources, People, Discovery.
- `App/Player/` — `PlaybackSession` (owns the playback in progress, outliving the player
  screen for Picture in Picture), `MPVPlayer` (libmpv, AVFoundation video layer),
  `ScrubPreview` (a second, silent mpv for timeline thumbnails), `PlayerView`, controls and
  menus, `PictureInPicture`, `NowPlaying`, next-episode countdown, tvOS remote swipe reader.
- `App/Settings/` — an index of pages: Sync, addons, TMDB, Home's shelves; playback
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
`--discovery-ui-test` with `-DISCOVERY_SCREEN <name>` opens a DEBUG fixture screen offline:
`recommended`, `my-lists`, `details`, `details-collection`, `series`, `details-unmatched`,
`details-busy`, `sources-folded|autoplay`
(need `Tools/test-addon.py --port 8769 --many --delay 5`), `sources-empty(-sheet)`,
`settings-review|failed`, `carousel-resume`. The playback fixture also takes
`PLAYBACK_FIXTURE_NEXT=late`, `PLAYBACK_FIXTURE_SHORT_URL` and `?hang=`.

## Conventions

- Before finishing: build all three platforms with no warnings, run Core tests, and check
  UI changes in the simulators (screenshots), including tvOS focus with the remote driver.
  Xcode's AppIntents metadata extraction warning is expected.
- Real-device testing isn't planned (ROADMAP.md): verify in simulators and automated tests,
  don't ask for or schedule hardware checks, and name what a simulator can't establish (HDR,
  display matching, remote swipes, screen lock, physical cross-device handoff) as a limit.
  macOS has no simulator; report Mac runtime behaviour as unverified unless checked.
- Reuse the existing tests and fixtures (`LibraryStoreTests`, `EpisodeScheduleTests`, `FlowTests`,
  `PlaybackRegressionTests`, `RemoteDriverTests`, `Tools/test-addon.py`, the playback
  fixtures) rather than creating another harness.
- Platform differences use `#if os(...)` in place; sizes live in `Metrics`
  (`App/Browse/Components/BrowseComponents.swift`), iPad/landscape via size classes. Phone-only
  behaviour checks the device (`Metrics.isPhone`), not the size class, so a narrow iPad window
  keeps its tabs.
- Expanding sync scope (e.g. Watch Later) or changing visible UI/interaction design
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
video output. Addons are added as manifest URLs. Cross-device sync is the optional self-hosted
account sync, never iCloud or a default hosted server; it carries progress, addons, playback
preferences and Home's layout (one field, conflicts asked about); Trakt support was removed in November
2026, and the accent colour setting the
same month: the app is always white. Sync is one person's devices only:
the live shared setups between accounts were removed the same month for a one-time setup copy
(`SetupCode`, `loge://setup#loge-setup-1:…`, base64url of deflated JSON; Share Setup on
iPhone/iPad/Mac, Import Setup everywhere). A device that was in a group drops its grants and
keys at launch and keeps what it shows; `Baselines.formerlyShared` makes the next sync take its
values for those categories over the account's older copy.
MDBList, which added Letterboxd and Rotten Tomatoes scores, was removed the same month
(`RetiredMDBListKey` deletes its saved key at launch).
Watch Later is the only list: custom lists were folded into it the same month (`LibraryStore`
appends any stored lists' titles once when a profile loads, then deletes them). My Lists ends
with Recently Watched, the last 12 titles finished and not in Continue Watching; removing one
there only hides it on this device, and its watched marks stay. iPhone/iPad and Apple TV are equal main devices.
Picture in Picture is required; downloads are out of scope; UI is English only for now.
iPhone browsing is portrait-only (`AppDelegate`); the player turns. iPad has one window
(`UIApplicationSupportsMultipleScenes` NO): every window would share the one `PlaybackSession`
and present its player; the Mac has no New Window either. Destructive settings and library
actions (addon removal, TMDB token, Sync disconnect, device revoke,
marking a season unwatched) ask first; importing a setup's Replace My Addons is its own
destructive-role confirmation. Dates and
numbers use `Locale.interface` (en_US) to match the English UI; clock times follow the device.
Person filmographies need TMDB: Cinemeta's search no longer names cast or directors, so
without TMDB the page says so and shows the title it came from. TMDB is what makes the
experience complete: without a token a title's page has no Cast & Crew at all, only the hint
to connect it (trailers are the exception and work without). A title's page leads with the
title and Play, with Watch Later and a More menu (trailer except on Apple TV, sources, watched mark)
beside it. A phone centres the three, Play in the middle at a fixed 172 pt and a size down
(`.controlSize(.small)`); wider screens start with Play. The description follows, and under it, one size down, genre, year, runtime and
the IMDb rating. It stands behind IMDb's white mark, the one place the app shows another
brand's logo. Rows on that page have a heading and no caption
under it. Section headings share a smaller semibold style across the app (20 pt on iOS).
More Like This and film collections show only the year below poster titles; filmography
keeps Movie/Series labels because it can mix both.

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
- Genre tiles push by value; a view-built destination left the links inside dead.
- tvOS Home's rows are a `LazyVStack`, so a row may not exist yet: the header is filled from
  the first shown catalog shelf in `TVHome`'s task, and loading rows keep the loaded row's height.
- Home's shelves come from `HomeLayout`, whose default is the old fixed order. An addon shelf
  is the addon's manifest `id` plus catalog type and `id`, never its URL (it carries keys and
  syncs); the URL is looked up in `AddonStore`. A shelf whose addon isn't on this device is
  skipped but kept, so it doesn't vanish from the others. Built-ins missing from a saved
  layout are appended, and unknown shelf kinds are dropped on decode.
- Home's artwork prefetch uses plain data tasks, not a task group (suspected Release crash).
  An optimizer bug once lost a task group's result in Release builds, so test Release too.
- iPad details switch between `DetailColumnsLayout` and a `VStackLayout` under `AnyLayout`,
  so rotating keeps the chosen season.
- The phone hero shows the portrait poster: a title near the top of a poster reads twice with
  the logo, and that can't be detected.
- The title's logo is `fixedSize` vertically on the details page: `TitleLogo` otherwise takes
  all the height it is allowed and a wide, low logo floats far above Play. With
  `restsOnLettering` it also lets sparkle or glow under the letters hang into the gap below
  (`LogoTrim` measures it; never cropped, and at most a third of the logo's height).
- A phone's Cast & Crew shows three portraits and the edge of a fourth (`personTileWidth`) with
  names only; who directed and wrote a title is in Information on every platform.
- The Mac player window is a principal window, since an associated one can't go full screen.
- The iOS timeline is a `Slider` to accessibility (10 s steps, spoken position), so FlowTests
  drag it rather than tap it.
- `StreamWarmup` GETs the one link Play would autoplay (from the title page) or Up Next found,
  without following the redirect: Comet resolves its link on the first request (most of the
  time to the first frame) and keeps it an hour. Never a source marked uncached (that starts a
  debrid download), never the whole list; the player still opens the addon's URL, not a saved one.
- The sources Filter's bitrate is the synced Maximum bitrate setting; audio and picture
  reset per list. `SyncedSettings` still writes the retired `maximumSourceGigabytes`
  (0 or 50) because older versions can't decode a setup without it; drop it once they're gone.
- Resuming past a shorter source's end seeks to 30 s before it instead of finishing; opening
  a stream fails with Try Again after 20 s.
- Navigation is the four tabs (Home, My Lists, Search, Settings) with `.tabBarOnly`, no sidebar
  anywhere. Search has the search role except on iPhone, where the role would detach it from
  the one pill; iPad and Mac draw it as the magnifier at the pill's trailing end.
- A series is followed while it has progress in the library: of the 30 most recently watched,
  `EpisodeSchedule` looks up those whose last episode was finished, at most every six hours
  each. An episode aired since then shows in Continue Watching as "New episode".
- Progress saved with `isEstimated` and a real fraction comes from the removed Trakt import;
  it still resumes by fraction, so keep that path.
- Trailers open on YouTube (addon `trailers`, or TMDB's list when connected); nothing in the
  app can play them, and Apple TV has no browser, so it offers none.
- `App/ScoreLogos.xcassets` holds IMDb's mark as a template SVG: its plate from Wikimedia
  Commons with the lettering merged into one even-odd path, because a template image keeps only alpha.
- Search's keyboard reappearing after going back is the system restoring a focused field;
  clearing focus on leaving doesn't stop it.

## Testing gotchas

- Playback UI tests expect the simulator in portrait; one left in landscape fails
  `testEpisodePausePersistsAndResumesAfterRelaunch`.
- `FlowTests.testTrackSwitchingWhilePlaying` is flaky: menus sometimes don't open in time.
- iPhone simulators lack Picture in Picture; use iPad for that path.
- `Test Streams` surviving uninstall on the iPhone 18 Pro simulator is a stale
  `data/Library/Preferences/li.tjh.MediaApp.plist` outside the app container.
- Skipped without setup: PiP tests on iPhone simulators, the connected-account test without a
  code file, TMDB filmography tests without a token file.
- Background-recovery tests check the picture's pixels; an older check couldn't see black video.

## Open

- Removable once every device has launched a build from `claude/trim-features`: `RetiredMDBListKey`,
  `LibraryStore.foldRetiredLists`, AccountSync's `RetiredGroups`/`formerlyShared`,
  `SyncedSettings.migrateSourceSizeLimit` and the decoding of `maximumSourceGigabytes`, and the
  gateway's retired `/v2/join` and `/v2/groups` routes and `groups: []`.
- ROADMAP.md lists the remaining verification item (OS runtime smoke tests) and the proposed
  features; agree on scope before building any of them.
- Cross-device sync: reviewed and fixed; proposed expansion (Watch Later)
  awaits a decision.
- Top Shelf is on hold: atvloadly installs the extension and its App Group
  (`group.li.tjh.MediaApp.<team ID>`, read from the embedded profile), but tvOS never launches
  it; the reason is only in the Apple TV's live log (branch `claude/top-shelf-test`).
- tvOS Home performance is measured in the simulator only (Release, Apple TV 4K, keys sent to
  the simulator rather than XCUIRemote): about 40 ms of main-thread work per move along a row
  and 140 ms between rows, down from 75 and 250 before the rows went lazy. Keep measurements
  comparable.
- Unverified: playback and Picture in Picture on tvOS and macOS, HDR output, tvOS display
  matching, swipe-to-scrub with the Siri Remote (the preview itself is checked in the
  simulators by setting a scrub position), physical phone-to-Apple-TV
  handoff, Mac sources rows with AIOStreams' long names, the Search genre
  pill and Watch Later row on Apple TV.
