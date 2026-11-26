# loge

loge: a Stremio-addon client for iPhone/iPad, Apple TV and Mac, in native SwiftUI, public on
GitHub under the PolyForm Noncommercial License 1.0.0 (source-available, no commercial use;
GPL-3.0 until 10 November 2026) and installed by sideloading (SideStore source, no App Store).
The project, scheme, product, `LogeCore` package and bundle ID (`li.tjh.loge`, also the
Keychain service names and log subsystem) are all named loge. Version 1.0 moved from the
working name's `li.tjh.MediaApp`: each device installed it as a new app and signed in to sync
and TMDB again; nothing reads the old app's data. It browses catalogs from Stremio addons, shows details,
lists streams and plays them with mpv. The look follows the Strand app: charcoal canvas,
artwork-led, white accent, system font, no cards/badges. Pages without a title sit on the
plain charcoal; a title's page, and Home's hero, sit in its room (`Room`): a deep
tone taken from the backdrop (`RoomTone`, cached per URL), which the backdrop fades into and
which fades to the canvas lower down. Heroes show the title's logo in white and greys
(`TitleLogo(isWhite:)`, desaturated with a soft dark shade, since flattening to one white loses
solid panels). Choices side by side (seasons, genres, lists, roles) are white-when-chosen pills
(`PillButtonStyle`; on Apple TV white when focused); posters in grids carry their name and a line
under. Apple TV shows focus by white fills and lift, never outlines: tiles lift 1.12 with a shadow
and the others dim (`LiftButtonStyle`), buttons and sentence values turn white. One white
primary button per screen; the rest translucent white, every button with a word. No end
times ("ends at"), only time left. Filters and settings read as sentences (`Sentence`): grey words, values white
and underlined, each value the menu or link that changes it.

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
- `App/Settings/` — by default one sentence under a large "loge" (which opens About), a line
  per setting, whose values are the controls (`SettingsSentencesView`: playback menus in place;
  addons, Home's shelves, TMDB and Sync open their pages), with Share Setup and Import Setup
  under it on iPhone/iPad. One paragraph (a single `Sentence`) whose values are the controls.
  No title or captions; on iPhone and iPad it starts at the top. On a wide iPad a value's page
  opens in a panel beside the sentence with the value marked (`TokenLabel(isMarked:)`); pages
  pushed from there take the screen. The Mac keeps it in the standard Settings window (⌘,),
  with Sparkle's switch, Check Now and the version under it, and has no Settings tab. The pages it opens are translucent groups of 52 pt rows under small grey labels, with
  white-track switches (`SettingsPage`, `SettingsToggleStyle`). "Settings read as sentences" switches
  this device to the plain list of the same. About (version, build commit, credits) and Data
  Sources, which holds all attribution rather than putting it under artwork.
- `web/` — the project page for loge.tjh.li: static HTML/CSS in tjh.li's design, no scripts
  or build step; `web/images` also serves the README and SideStore source. Cloudflare Pages
  (project `loge`), deployed by `.github/workflows/web.yml` when `web/` changes on main.
- `Tools/sync-gateway` — self-hostable account sync (gateway in front of a private CouchDB,
  local admin page); see docs/SYNC.md. Personal infrastructure lives in a separate private repo.
- `Tools/install.sh` — the one install script: Release of origin/main (own checkout in
  `.build/install`) or this checkout, onto a reachable iPhone/iPad (free Personal Team), the
  Apple TV via atvloadly, or all, from a menu or named.
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
Tools/install.sh                                    # latest main on a device picked from a menu
Tools/install.sh --debug --launch phone             # this checkout, Debug, on the iPhone/iPad (--console streams output)
Tools/install.sh --here tv                          # this checkout on the Apple TV via atvloadly
```

Devices normally install from the SideStore source. `install.sh` signs phones with the free
Personal Team in Xcode; the phone needs Developer Mode and the developer trusted once; free
installs expire after 7 days. atvloadly runs on a home-network server (`ATVLOADLY`, default in
`install.sh`) and re-signs nightly 03:00–06:30. A free Apple ID allows 3 sideloaded apps
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
`details-busy`, `sources-folded|autoplay|sheet`
(need `Tools/test-addon.py --port 8769 --many --delay 5`), `sources-empty(-sheet)`,
`settings-review|failed|old-server`, `carousel-resume` (a series started: the phone's resume
hero), `home-empty` (first launch: nothing watched, no addons), `search-results` (with a TMDB
person), `catalog` (See All), `my-lists-artwork`, `home-shelves`, `addons`, `settings`, `person`, `root`
(the whole window, with the tabs and the Mac's toolbar). `details` and `series` take
Cinemeta rather than the simulator's addons; `series` has S1 E1 watched and E2 started.
`DiscoverySnapshotTests` captures them on iPhone, iPad and Apple TV (`TEST_RUNNER_DISCOVERY_SCREENSHOT_DIR`, `_SCREENS`,
`_SETTLE` seconds, `_SCROLLS`). Fixture screens run with throwaway settings and an offline sync
account (`loge.ui-test`), never this device's own, so they also work on a Mac that has the real
app set up: build Debug for macOS, then `open --env DISCOVERY_SCREEN=<name>
.build/xcode/Build/Products/Debug/loge.app --args --discovery-ui-test` (not `open -n`, and no
extra arguments, or no window opens; the screen must be unlocked) and capture it with
`screencapture -l <window id>`. Launching it any other way runs against the real settings.
The fixtures leave `loge.*-fixture` plists in `~/Library/Preferences`. The playback fixture also takes
`PLAYBACK_FIXTURE_NEXT=late`, `PLAYBACK_FIXTURE_SHORT_URL` and `?hang=`.

## Conventions

- Before finishing: build all three platforms with no warnings, run Core tests, and check
  UI changes in the simulators (screenshots), including tvOS focus with the remote driver.
  Xcode's AppIntents metadata extraction warning is expected.
- Real-device testing isn't planned (ROADMAP.md): verify in simulators and automated tests,
  don't ask for or schedule hardware checks, and name what a simulator can't establish (HDR,
  display matching, remote swipes, screen lock, physical cross-device handoff) as a limit.
  macOS has no simulator: check Mac screens with the fixtures as described under Commands,
  and report what they don't reach (typing into search, hover, the player) as unverified.
- Reuse the existing tests and fixtures (`LibraryStoreTests`, `EpisodeScheduleTests`, `FlowTests`,
  `PlaybackRegressionTests`, `RemoteDriverTests`, `Tools/test-addon.py`, the playback
  fixtures) rather than creating another harness.
- Platform differences use `#if os(...)` in place; sizes live in `Metrics`
  (`App/Browse/Components/BrowseComponents.swift`), iPad/landscape via size classes. Phone-only
  behaviour checks the device (`Metrics.isPhone`), not the size class, so a narrow iPad window
  keeps its tabs.
- Expanding sync scope (e.g. remembered sources) or changing visible UI/interaction design
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
account sync, never iCloud or a default hosted server; it carries progress, Watch Later (its own
`watchLater` document: per title the latest addition or removal wins, removals kept 90 days,
no prompts; an older gateway's 404 keeps it on the device), addons (with the names given them
and whether their sources are combined), playback preferences and
Home's layout (one field, conflicts asked about); Trakt support was removed in November 2026,
and the accent colour setting the same month: the app is always white. Sync is one person's devices only:
the live shared setups between accounts were removed the same month for a one-time setup copy
(`SetupCode`, `loge://setup#loge-setup-1:…`, base64url of deflated JSON; Share Setup on
iPhone/iPad/Mac, Import Setup everywhere). A device that was in a group drops its grants and
keys at launch and keeps what it shows; `Baselines.formerlyShared` makes the next sync take its
values for those categories over the account's older copy.
MDBList, which added Letterboxd and Rotten Tomatoes scores, was removed the same month.
Watch Later is the only list: custom lists were folded into it the same month (`LibraryStore`
appends any stored lists' titles once when a profile loads, then deletes them). My Lists ends
(on iPhone: a second pill beside Watch Later, both as poster grids, a film's runtime under its
name) with Recently Watched, the last 12 titles finished and not in Continue Watching; removing one
there only hides it on this device, and its watched marks stay. iPhone/iPad and Apple TV are equal main devices.
Picture in Picture is required; downloads are out of scope; UI is English only for now.
iPhone browsing is portrait-only (`AppDelegate`); the player turns. The iPad is landscape
only, player included (project.yml and `AppDelegate`). iPad has one window
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
title and Play. On iPhone: the logo centred, one line of genre, year, runtime and the IMDb
rating, Play ("Resume S2 E4") across the width, then four labelled circles (Watch Later,
filled as "In Watch Later"; Trailer; Sources, a sheet; Watched, which for a series marks or
clears every aired episode and asks before clearing), then the description in three lines.
Episodes are rows under season pills; Information is a two-column table. iPad and Mac use the
same column on the left (left-aligned, Information under it) and put episodes (200 pt stills
with their summaries), Cast & Crew, the collection and More Like This on the right, under the
backdrop, which takes the top right and fades left into the room. The Mac's left column is a
fixed 460 pt (a wider window gives the room to the right side), with Play across it and the
actions as small worded capsules (no icons) under it, wrapping to two rows when they don't fit; the
menu bar's Title menu has the same actions (Play ⌘↩, Watch Later ⌘L, Sources ⌘⇧S, Watched)
for the title in the key window (`TitleCommands`, a focused scene value), and Go has Home ⌘1
and My Lists ⌘2. Apple TV leads with the logo, facts and two lines of description,
then worded buttons (Play focused, Watch Later, Sources, Watched; no Trailer), "31 min left"
under them, season pills over 390 pt episode cards (the pills take focus only after an
episode has, so one press down from Play reaches the episodes) and More Like This first
below. The facts line shows genre, year, runtime and
the IMDb rating. It stands behind IMDb's white mark, the one place the app shows another
brand's logo. Rows on that page have a heading and no caption
under it. Section headings share a smaller semibold style across the app (20 pt on iOS).
More Like This and film collections show only the year below poster titles; filmography
keeps Movie/Series labels because it can mix both, except on a phone, which shows the year and
filters by role pills (All, Actor, Director, Crew), newest first.
iPhone Search opens on recent searches and genre tiles; typing lists titles as rows across both
catalogs, and with TMDB someone whose name matches comes first (`TMDBAccount.person(named:)`,
TMDB's top match only). Its filter sentence shows once there's a query or genre.

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
- iPad and Mac details switch between `DetailColumnsLayout` and a `VStackLayout` under
  `AnyLayout` when the window narrows below 880 pt, so the chosen season survives.
- Posters and cards, Continue Watching's included, always open the title's page, never its
  sources; their context menu (long press, or right-click on the Mac) has Watch Later and, for
  a film, its watched mark (`TitleActionsMenu`). On the Mac a shelf reached with Tab pages with
  ← and →; playing is that page's Play (or the Home hero's Resume). On the Mac hovering
  artwork (`PointerHighlight`) dims it, with a white Play button only on a title page's
  episode stills, which open their sources. The Mac's sources sheet has Play picks
  selectable like any row, Cancel and Play, Return plays the selection, and a row's tooltip
  shows the file's release name. Release names carry no addon keys; only manifest and stream
  URLs do, and those are never shown.
- Home leads with what's being watched (full width with Details beside Resume on iPad and Mac) (`ResumeHero`: the latest of Continue
  Watching, Resume going through Sources with autoplay, the rest a
  swipe away and in the row under it), unless Continue Watching is hidden in Home's layout;
  otherwise the featured carousel, with Play and Details. Without a stream addon a card under
  the hero offers Add Addon and Import Setup. Hero backdrops are the landscape image.
- Posters on a phone's shelves carry the name and "year · IMDb rating" (`isCaptioned`).
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
- The sources list's bitrate filter is the synced Maximum bitrate setting, and Cached only the
  synced `cachedOnly` (hides what an addon marks uncached: "[xx download]", ⏳, "uncached";
  unmarked sources stay); both also limit what Play starts by itself. Audio and picture
  reset per list. `SyncedSettings` still writes the retired `maximumSourceGigabytes`
  (0 or 50) because older versions can't decode a setup without it; drop it once they're gone.
- Resuming past a shorter source's end seeks to 30 s before it instead of finishing; opening
  a stream fails with Try Again after 20 s.
- Navigation is the four tabs (Home, My Lists, Search, Settings) with `.tabBarOnly`, no sidebar
  anywhere. Search has the search role except on iPhone, where the role would detach it from
  the one pill; the iPad draws it as the magnifier at the pill's trailing end. The Mac has
  Home and My Lists only: search is the toolbar field (⌘F), whose results cover the tab while
  it has text (`SearchView(toolbarQuery:)`), and Settings is its own window, opened by ⌘, or
  the gear beside the field. The field is a 220 pt one of the app's own: `.searchable`'s fills
  all of the Mac toolbar's free space.
- A series is followed while it has progress in the library: of the 30 most recently watched,
  `EpisodeSchedule` looks up those whose last episode was finished, at most every six hours
  each. An episode aired since then shows in Continue Watching as "New episode".
- Progress saved with `isEstimated` and a real fraction comes from the removed Trakt import;
  it still resumes by fraction, so keep that path.
- Trailers open on YouTube (addon `trailers`, or TMDB's list when connected); nothing in the
  app can play them, and Apple TV has no browser, so it offers none.
- `App/ThirdParty/Logos.xcassets` holds IMDb's mark as a template SVG: its plate from Wikimedia
  Commons with the lettering merged into one even-odd path, because a template image keeps only alpha.
- Live sync: `AccountSync.startLiveUpdates()` on launch and on return, `stopLiveUpdates()` on
  background (the Mac rarely backgrounds, so it keeps listening). The listener ends quietly on a
  gateway's 404 and is tried again on the next return; its retries never touch `status`.
  Documents are fetched with `If-None-Match` against an in-memory copy, so a relaunch fetches
  them in full once; `me()` runs once per launch or connect, and again after a 401.
- Sources come from one stream addon at a time (the one last picked in the list's Addon menu,
  `[StreamProvider].chosenAddonKey`, this device only; else the first) unless Settings → Addons
  combines them. On iPhone, iPad (a centred panel with Close) and Mac the list is one, best first, each row with its resolution
  boxed; the filters are a Filter menu, and "Play picks" shows the source autoplay would
  start (`continuingSource()`, the same code), shown only when there's a remembered source. Play, autoplay, fallbacks and the title page's prefetch all go through
  `chosen(_:combined:)`; a remembered source from another addon doesn't autoplay.
- Search's keyboard reappearing after going back is the system restoring a focused field;
  clearing focus on leaving doesn't stop it.

## Testing gotchas

- Playback UI tests expect the simulator in portrait; one left in landscape fails
  `testEpisodePausePersistsAndResumesAfterRelaunch`.
- `FlowTests.testTrackSwitchingWhilePlaying` is flaky: menus sometimes don't open in time.
- iPhone simulators lack Picture in Picture; use iPad for that path.
- `Test Streams` surviving uninstall on the iPhone 18 Pro simulator is a stale
  `data/Library/Preferences/li.tjh.loge.plist` outside the app container.
- Skipped without setup: PiP tests on iPhone simulators, the connected-account test without a
  code file, TMDB filmography tests without a token file.
- Background-recovery tests check the picture's pixels; an older check couldn't see black video.

## Open

- Removable once every device has launched a build from `claude/trim-features` (or 1.0, which
  every device installs fresh): `LibraryStore.foldRetiredLists`, AccountSync's `RetiredGroups`/`formerlyShared`,
  `SyncedSettings.migrateSourceSizeLimit` and the decoding of `maximumSourceGigabytes`, and the
  gateway's retired `/v2/join` and `/v2/groups` routes and `groups: []`.
- ROADMAP.md lists the remaining verification item (OS runtime smoke tests) and the proposed
  features; agree on scope before building any of them.
- Top Shelf is on hold: atvloadly installs the extension and its App Group
  (`group.li.tjh.loge.<team ID>`, read from the embedded profile), but tvOS never launches
  it; the reason is only in the Apple TV's live log (branch `claude/top-shelf-test`).
- tvOS Home performance is measured in the simulator only (Release, Apple TV 4K, keys sent to
  the simulator rather than XCUIRemote): about 40 ms of main-thread work per move along a row
  and 140 ms between rows, down from 75 and 250 before the rows went lazy. Keep measurements
  comparable. Simulator.app has since gone from this machine, so the Rooms Home (focused
  title's room tone, tone computed off the main thread) was compared with XCUIRemote presses
  instead, which add their own stall: before and after, about 130 ms per move along a row
  both, and 23–35 ms vs 33–35 ms between rows (`sample`, two runs each). Not comparable with
  the numbers above.
- Unverified: playback and Picture in Picture on tvOS and macOS, HDR output, tvOS display
  matching, swipe-to-scrub with the Siri Remote (the preview itself is checked in the
  simulators by setting a scrub position), physical phone-to-Apple-TV
  handoff, Mac sources rows with AIOStreams' long names, the Search genre
  pill and Watch Later row on Apple TV.
