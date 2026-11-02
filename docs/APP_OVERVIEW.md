# Loge: implementation overview

Updated 2 November 2026. See [HANDOFF.md](HANDOFF.md) for the latest batch, verification and remaining work. Loge is a private SwiftUI streaming app for
iPhone, iPad, Apple TV and Mac. `MediaApp` remains the project, scheme and bundle
identifier so existing installations keep their data.

## Application and data flow

`App/MediaApp.swift` creates five observable, main-actor owners and injects them
through the SwiftUI environment: `AddonStore`, `LibraryStore`, `TraktAccount`
`PlaybackSession` and `TMDBAccount`. Each browsing tab has its own navigation stack. Movies,
series, catalog grids and source lists use typed navigation destinations.

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
6. `TraktAccount` signs in with a device code, scrobbles playback and imports
   remote playback progress. Startup pulls progress after manifest refresh.

## Screens and platform behavior

- `App/Browse/HomeView.swift`: artwork carousel on iPhone/iPad/Mac; a
  focus-driven backdrop and fixed title header on Apple TV. Fixed popular,
  IMDb-favourites and genre shelves replace addon-ordered Home catalogs.
- `CatalogRow.swift` and `CatalogGridView.swift`: poster rows and paginated
  grids, with genre filtering when the addon advertises it.
- `MetaDetailView.swift`: title details, seasons, episode cards, watched
  actions and next episode selection.
- `PersonView.swift`: Cast & Crew on details and a person's titles, found by
  searching Cinemeta for the name and keeping results that credit them.
- `SourcesView.swift`: source selection, autoplay and fallback candidates. Resolution
  groups retain addon order for ties, with cached-first, bitrate and file-size
  sorting plus a reported-bitrate cap; unknown rates stay visible.
- `SearchView.swift`: debounced search across built-in movie/series feeds and local
  recent searches.
- `App/Settings`: addon installation/order/removal, playback preferences and
  Trakt app keys/sign-in/sync.

The shared visual language lives in `BrowseComponents.swift`: charcoal canvas,
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

IMDb scores supplied by Cinemeta are labelled with their source and ten-point
scale. Movie details on iOS/Mac link to Letterboxd using its documented IMDb-ID
redirect. Letterboxd ratings are not fetched: its API is request-only and the
user chose IMDb scores plus Letterboxd links. Home's shelves are managed
discovery feeds, not recommendations inferred from viewing history.

## Persistence and privacy

Library data, installed addon configuration and playback preferences use
UserDefaults because tvOS may purge app files. Progress history is bounded to
500 entries. Trakt keys and tokens use Keychain; the username is stored in
UserDefaults. This means installed addon configuration is sensitive local
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
- Look up unavailable title metadata once per Trakt progress pull, even when
  several paused episodes belong to that title.

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

- Trakt refresh requests can overlap; in-flight authentication/sync work needs
  explicit coordination with sign-out and changed app keys. Add an injectable
  transport and lifecycle tests before changing that flow.
- Verify tvOS swipe scrubbing, actual subtitle sizing, Picture in Picture and
  audio/session behavior on real devices. Simulator checks cannot establish
  hardware decoder, HDR or Siri Remote touch behavior.
- Profile image decoding and long catalog scrolling before introducing a new
  image loader or cache. The app already configures a shared URL cache.

## Verification workflow

Run `swift test` in `Core`, then build the `MediaApp` scheme for
`generic/platform=iOS Simulator`, `generic/platform=tvOS Simulator` and
`platform=macOS`. Use `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` to catch Swift warnings.
Run `xcodegen generate` after adding/removing Swift source files.

`UITests/FlowTests.swift` contains opt-in iOS flows, enabled with
`TEST_RUNNER_UI_FLOWS=1`. They depend on live catalog content; playback checks
also require `Tools/test-addon.py`. Set `TEST_RUNNER_SCREENSHOT_DIR` to retain
screenshots. `RemoteDriverTests.swift` drives tvOS focus/navigation with an
opt-in command file. `PlayerMenuTests.swift` covers player interactions on
request. Keep fixture requests separate from private stream-addon credentials.

See [REVIEW_VALIDATION.md](REVIEW_VALIDATION.md) for this review's actual results
and limitations.
