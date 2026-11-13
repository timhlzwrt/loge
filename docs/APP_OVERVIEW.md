# loge: implementation overview

Updated 7 November 2026. loge is a SwiftUI streaming app for
iPhone, iPad, Apple TV and Mac. `li.tjh.MediaApp` remains the bundle
identifier so existing installations keep their data.

## Application and data flow

`App/LogeApp.swift` creates seven observable, main-actor owners and injects them
through the SwiftUI environment: `AddonStore`, `LibraryStore`, `EpisodeSchedule`,
`PlaybackSession`, `TMDBAccount`, `MDBListAccount` and `AccountSync`. Each browsing tab has its own
navigation stack. Movies, series, catalog grids and source lists use typed
navigation destinations.

1. `AddonStore` loads the installed addon list and cached manifests from
   UserDefaults. Startup refreshes manifests concurrently, preserving cached
   capabilities if a refresh fails. Fresh installs have no addons; restore removes
   the exact old built-in Cinemeta entry while retaining every custom addon.
2. `AddonManifest` describes catalog, metadata, stream and subtitle capabilities.
   `AddonRouting` selects eligible providers in installation order.
3. `AddonClient` builds Stremio resource URLs and decodes HTTP JSON responses.
   Configured URL paths and queries are opaque; they can contain credentials.
4. `DiscoveryCatalogs` defines seven managed public Cinemeta shelves and movie/series
   search feeds. These work without installed addons. Installed metadata providers
   keep priority, with built-in Cinemeta fallback for IMDb movie/series IDs.
   Source lists collect provider
   responses, group playable streams, and try the remembered source when asked
   to autoplay. `StreamCache` joins in-flight source requests and reuses successful
   lists for ten minutes, including prefetches from details. A canceled source
   screen cannot autoplay when that shared request later completes.
   Torrents without a playable URL are excluded.
5. `PlaybackSession` opens a `PlaybackRequest`, owns the player lifecycle and
   persists progress. `LibraryStore` supplies Continue Watching, My List,
   watched status, remembered sources and Up Next.
6. `EpisodeSchedule` looks up the episode lists of the series being watched (those with
   progress, the 30 most recent, each at most every six hours) and works out from the
   library which episode is new since the last one was finished and which airs next.
7. `AccountSync` optionally connects to the self-hosted account gateway, carrying
   encrypted progress, watched state, addon setup and preferences. Separate shared
   setup categories never include private viewing progress. See [Private sync](SYNC.md).

## Screens and platform behavior

- `App/Browse/Home/HomeView.swift`: artwork carousel on iPhone/iPad/Mac; a
  focus-driven backdrop and fixed title header on Apple TV. Fixed popular,
  IMDb-favourites and genre shelves replace addon-ordered Home catalogs.
- `CatalogRow.swift` and `CatalogGridView.swift`: poster rows and paginated
  grids, with genre filtering when the addon advertises it.
- `MetaDetailView.swift`: title details, seasons, episode cards, watched
  actions and next episode selection. Cast & Crew shows only with TMDB connected;
  the addon's credits then stand in while TMDB's load or when it has none. A Trailer
  button opens YouTube (the addon's trailer, or TMDB's when connected; on Apple TV
  only with the YouTube app installed), and a movie in a TMDB collection lists that
  film series in release order.
- `PersonView.swift`: person details and role-filtered TMDB filmographies when
  connected. Without TMDB it says a filmography needs TMDB and shows the title the
  person was opened from: Cinemeta's search no longer names cast or directors. That
  state is only left for a page still open when TMDB is disconnected.
- `SourcesView.swift`: source selection, autoplay and fallback candidates. Resolution
  groups retain addon order for ties, with cached-first, bitrate and file-size
  sorting plus a reported-bitrate cap; unknown rates stay visible.
- `SearchView.swift`: debounced search across built-in movie/series feeds and local
  recent searches.
- `App/Settings`: addon installation/order/removal, playback preferences,
  self-hosted sync/sharing, the TMDB and MDBList connections and the Mac updater.

The shared visual language lives in `App/Browse/Components`: charcoal canvas,
white controls, artwork-led hierarchy, platform-specific `Metrics` and font
sizes. Platform differences stay inline behind `#if os(...)`. Mac playback
uses a separate window; iOS/tvOS use a full-screen presentation.

## Playback ownership

`PlaybackSession` outlives `PlayerView`, allowing Picture in Picture to keep
playing after the controls close. It owns `MPVPlayer`, Picture in Picture and
Now Playing, records progress roughly every ten seconds, loads external
subtitles and episode metadata, and prepares the next episode near the end.

`MPVPlayer` wraps libmpv, reads events off the main actor and applies observable
state on the main actor. UI position updates are rounded to whole seconds.
`MPVVideoView` presents the video layer; `PlayerControls`, `PlayerPanel` and
`PlayerView` handle interaction and presentation. `ScrubPreview` opens a separate,
silent mpv decoder only when scrubbing starts, then releases it after thirty
seconds without scrubbing. Transport seeks and preview load/seek/quit commands
are submitted asynchronously; PiP additionally waits for playback to restart
before completing AVKit's skip request. The vendored MPVKit build
contains resize, subtitle and frame-presentation timing patches; see
`Vendor/MPVKit/README.md` before replacing it. Automatic source choices default
to a 50 GB per-episode limit for series only, based on explicit video-file sizes.
Movies and manual source choices are unrestricted. See
[playback performance](PLAYBACK_PERFORMANCE.md) for behavior and diagnostics.

A title's page shows its scores behind each site's mark (`ScoresLine`): IMDb's from
Cinemeta, and with an MDBList key the Letterboxd average (out of 5) and Rotten Tomatoes'
Tomatometer, which neither site offers through an open API of its own. On iOS and Mac
each score opens the title there: IMDb and Letterboxd by IMDb ID, Rotten Tomatoes by the
address MDBList supplies. Elsewhere, such as Home, the IMDb score stays text with its
ten-point scale. Home's shelves are managed
discovery feeds, not recommendations inferred from viewing history.

## Persistence and privacy

Library data, installed addon configuration and playback preferences use
UserDefaults because tvOS may purge app files. Progress history is bounded to
500 entries. The TMDB token, MDBList key and sync credentials use Keychain. This means installed addon configuration is sensitive local
preference data, not Keychain-protected data.

Never copy a configured stream-addon manifest URL into docs, logs, screenshots
of editable fields, fixtures or issue reports. Use synthetic URLs in tests and
only the host when describing an installed addon. Do not dump simulator app
preferences while diagnosing a failure.

## Changes from this review

- Carry forward the existing release-date comparison workaround for a missing
  Foundation symbol on iOS 27.2 betas; this was present during simulator testing.
- Preserve encoded addon configuration paths and correctly place resource
  paths before URL queries/fragments.
- Ignore canceled catalog responses; isolate grid loads from obsolete genre
  requests and remove duplicate IDs within incoming pages.
- Clip the featured carousel to its viewport so a neighboring page cannot
  bleed into the iPhone's landscape safe area.
- Cancel superseded Now Playing artwork and subtitle work, avoid retaining
  completed artwork tasks, and reject obsolete episode metadata.
- Reset a source's custom User-Agent before opening a source without one;
  update the system playback rate when speed changes.
- Center transport independently of the player bars; keep timing adjustments
  within the viewport and avoid early Up Next prompts on short clips.
- Wait for PiP startup before removing the source screen, preserve video during
  automatic handoff, synchronize AVKit's playback queries, and detach callbacks
  during teardown. Replacing a source keeps the player screen mounted.
- Make Up Next deterministic after marking a whole season watched. Preserve
  estimated runtimes and replay finished estimated items from the beginning.
- Reject nonfinite progress values, clamp imported fractions and enforce the
  progress limit for manual and remote writes as well as playback writes.
- Discard canceled source, details and person responses before publishing state;
  source cancellation also prevents delayed autoplay and fallback changes.
- Preserve binary file-size units when comparing sources, so GiB and GB sort
  according to their actual byte counts.

These changes reduce wasted work and bound retained state. No frame-rate,
memory or launch-time improvement is claimed without profiling.

The performance follow-up makes Home's vertical rows lazy on iOS/Mac, checks
one featured title's resume state without sorting the whole library, and skips
clock-rate checks on mpv's per-frame position events. See the validation notes
for the scoped synthetic benchmark; it is not an overall app speed measurement.

Audio/subtitle selections and external subtitle loading use serialized async
mpv commands. Pending selections for the same track type are coalesced; manual
choices take priority over subtitle downloads. A later subtitle download cannot
replace an explicit subtitle choice. Track metadata is copied from mpv's
track-list event rather than queried property by property across mpv's core lock.
The next file waits for an outstanding track command to finish or cancel, so
old subtitle work cannot attach to a replacement file.

## Follow-up work

The [roadmap](../ROADMAP.md) tracks simulator/automated-test priorities and proposed
features. Real-device testing isn't planned because of maintainer time constraints.

- The self-hosted account syncs playback and setup separately; keep its ownership
  boundaries explicit in tests.
- Exercise subtitle sizing, supported Picture in Picture flows and
  background/foreground playback in simulators. Simulator checks cannot establish
  hardware decoder, HDR or physical Siri Remote touch behavior.
- Profile image decoding and long catalog scrolling before introducing a new
  image loader or cache. The app already configures a shared URL cache.

## Verification workflow

Run `swift test` in `Core`, then build the `loge` scheme for
`generic/platform=iOS Simulator`, `generic/platform=tvOS Simulator` and
`platform=macOS`. Use `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` to catch Swift warnings.
Run `xcodegen generate` after adding/removing Swift source files.

`UITests/FlowTests.swift` contains opt-in iOS flows, enabled with
`TEST_RUNNER_UI_FLOWS=1`. They depend on live catalog content; playback checks
also require `Tools/test-addon.py`. Set `TEST_RUNNER_SCREENSHOT_DIR` to retain
screenshots. `RemoteDriverTests.swift` drives tvOS focus/navigation with an
opt-in command file. `PlayerMenuTests.swift` covers player interactions on
request. Keep fixture requests separate from private stream-addon credentials.

`PlaybackRegressionTests.swift` uses the existing local multi-audio fixture
(`TEST_RUNNER_PLAYBACK_FIXTURE_URL=http://127.0.0.1:8766/tracks.mov`). It covers
episode progress across pause/relaunch, remote percentage-to-duration correction,
source replacement, audio and subtitle changes, and recovery after backgrounding and
the simulator's lock button: picture (checked in the screenshot's pixels), timeline,
controls and mpv's A/V offset. Run it on an iPad too: iPhone simulators have no Picture
in Picture, so they take the path that pauses, while real iPhones and iPads keep playing.
Actual screen-lock recovery is outside simulator verification and isn't a planned
hardware-testing task. `DiscoveryTVTests` uses the same fixture for the remote's path through the player on
tvOS: skip offers, Up Next (`PLAYBACK_FIXTURE_NEXT=1` offers a next episode, `late` only
after the end), the end card, the panel, Sources and the failure screen. A
`?fail-once=<anything>` query on the fixture's URL fails its first request, for Try Again;
`?hang=<anything>` never starts, for the 20-second open timeout.
`TEST_RUNNER_PLAYBACK_FIXTURE_SHORT_URL` (a clip under 30 s, such as a second test addon
on :8767) adds a switch to a shorter source.
Source-focus and addon-removal checks use an isolated addon store. Run a second
`Tools/test-addon.py` without `--tracks-file` on port 8765 and set
`TEST_RUNNER_DISCOVERY_ADDON_URL=http://127.0.0.1:8765/manifest.json` for these checks.
`DiscoveryTVTests.testLibraryFocusMovesBetweenRows`
and the remote driver's `TEST_RUNNER_DISCOVERY_SCREEN=library` use an isolated
library fixture for navigation checks without changing the user's saved titles.
