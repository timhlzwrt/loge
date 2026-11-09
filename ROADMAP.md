# Roadmap

[Back to loge](README.md)

**Status: pre-1.0.** This is a small, actively developed client. The priorities
are reliable playback and clear cross-device behavior—not a list of promised
release dates. This roadmap reflects the source as of **9 November 2026**.

## Shipped

- [x] Native iPhone, iPad, Apple TV and Mac browsing and playback.
- [x] Built-in Cinemeta discovery/search, genre shelves, festival editions,
  director discovery and optional TMDB metadata, filmographies and reviews.
- [x] TMDB-based recommendations: More Like This on details and a Recommended
  Home row ranked on the device from watched and saved titles.
- [x] Addon management, structured source selection, remembered sources,
  connection-aware recommendations and automatic fallback.
- [x] mpv playback, subtitles and timing controls, timeline previews,
  available chapter/community skips and automatic next episodes.
- [x] Continue Watching, episode resume, Up Next, Watch Later, custom lists
  and day-grouped viewing history.
- [x] Trakt device-code sign-in, scrobbling, paused-progress import,
  watched/unwatched updates, removals, and offline changes sent on reconnect.
- [x] Optional encrypted self-hosted accounts with progress, watched state,
  addons and preferences; offline merging, the newest position winning, and a
  choice when a title was removed on one device and played on another.
- [x] Scoped shared setups, separate private progress, expiring invitations,
  device revocation and a local service administration page.
- [x] GitHub release assets for iOS/tvOS/Mac, a SideStore source, a Mac
  drag-to-Applications installer and signed Sparkle updates.

“Shipped” means implemented in the code, not validated on every hardware or
provider combination.

## A note from the maintainer

I don't have the time to carry out real-device testing, so it won't be part of the
planned work or a release requirement. Testing focuses on iPhone, iPad and Apple TV
simulators, plus automated tests and Mac builds. Hardware-testing tasks are not on
this roadmap.

That doesn't make simulator checks equivalent to hardware checks. Actual HDR output,
HDMI frame-rate/dynamic-range switching, physical Siri Remote gestures and screen-lock
recovery aren't established by simulator results. These limitations stay documented
rather than becoming promises to test them later. macOS has no simulator; a Mac build
alone doesn't verify playback or Picture in Picture at runtime.

## Next: verification first

- [x] Extend the existing local playback fixture for pause, relaunch, resume,
  source replacement, subtitle/audio changes and background/foreground recovery.
  Exercise Picture in Picture only where the simulator supports it; record
  unsupported cases as skipped, not passed.
- [x] Test independent account stores for offline changes, reconnect, conflicting
  progress, explicit removals and sign-out. Exercise account connection and sharing
  UI in simulators. Use controlled fixtures for Trakt responses; no physical
  phone-to-TV handoff or live-provider check is a release prerequisite.
- [x] Cover fresh installs, browse-to-play and returning from playback on iPhone
  and iPad, including landscape. Use the existing tvOS remote driver for button-based
  focus/navigation checks, retaining screenshots. Don't treat those checks as
  physical swipe or frame-pacing measurements.
- [ ] Run the existing Core tests and warning-as-error builds for all three
  platforms. Smoke-test supported OS simulator versions when their runtimes are
  available, and report exactly which runtimes ran. A deployment target or successful
  compilation isn't proof of runtime compatibility.
- [x] Check packaged Release builds and update feeds advertise the same minimums
  as the app and LogeCore. Build 127's iOS and tvOS `.ipa` files, Mac `.dmg`, Sparkle
  feed and SideStore source all say 26.0 (checked by hand on 9 November; the source
  files stay covered by a Core test, the artifacts by no automated check).

Reuse `UITests/PlaybackRegressionTests.swift`, `UITests/FlowTests.swift`,
`UITests/DiscoveryTVTests.swift`, `UITests/RemoteDriverTests.swift` and the Core test
suites instead of creating another test harness. See the
[verification workflow](docs/APP_OVERVIEW.md#verification-workflow).

## Features worth exploring

These are proposals, not promised releases. Agree on scope and interaction design
before implementation.

### 1. Sync Watch Later and custom lists

Playback progress and setup already sync through the optional self-hosted account;
Watch Later and custom lists should be considered separately. Carry list membership,
names and deliberate removals between a person's devices, with defined offline-merge
rules. Keep these lists private to the account, not part of addon-sharing invitations.
This would expand sync scope and needs agreement before implementation.

**Test target:** independent stores converge after concurrent additions, renames and
removals; reconnect doesn't resurrect deleted entries; another account can't read them.

### 2. Search installed addons

Search currently uses the built-in movie and series feeds. Offer opt-in search of
installed catalogs that advertise search support, preserving addon order and showing
results as each provider responds. A slow or failing addon must not block other results.
Keep built-in search as the default to avoid sending every query to every provider.

**Test target:** fixture addons cover partial failure, delayed responses, duplicate
titles and changing the query before earlier responses finish.

### 3. Narrow sources by audio, HDR and codec

Build on the existing source details, sorting and bitrate limit: let users narrow a
long list by reported audio language, dynamic range or codec. Keep unknown metadata
visible unless explicitly excluded, and provide a clear reset when no sources match.
These are metadata filters, not guarantees about what a device can decode or display.

**Test target:** deterministic source fixtures cover mixed and missing metadata, empty
results, filter reset and tvOS focus after the list changes.

### 4. Arrange Home shelves

Let people hide shelves they don't use and reorder the rest, without changing the
artwork-led layout. Start with local preferences and a reset to the default order;
sharing or syncing that layout would be a separate decision.

**Test target:** simulator flows cover persistence after relaunch, default restoration,
hidden/empty shelves and predictable Apple TV focus after reordering.

## On hold

**Apple TV Top Shelf.** An earlier extension could be signed and installed
through the sideloading setup, but tvOS did not launch it. Further investigation
depends on physical device logs and behavior, so it isn't planned. There is no
Top Shelf support in the shipped app.

**More scrolling/image-cache work.** Profile image decoding and long catalog
scrolls first. Keep measured regressions separate from speculative rewrites.

## Not in scope

- Offline downloads, a torrent engine or built-in content hosting.
- A default hosted sync backend or iCloud sync.
- Promised App Store distribution, notarization or Intel Mac support.
- A server-side recommendation engine (recommendations are ranked on the device
  from TMDB's suggestions) or Letterboxd account/rating integration.
- Interface localization is not scheduled; the UI is currently English.

Watch Later/custom-list sync is **not implemented**. Any expansion of the
current sync contract needs an explicit scope decision, not an unchecked
feature claim.

## Help move this forward

Useful contributions include reproducible bugs, focused fixes, and test results
that identify the **device, OS, build commit and exact scenario**. Propose new
features through the [issue forms](https://github.com/timhlzwrt/loge/issues/new/choose)
before starting a broad implementation. See [Contributing](CONTRIBUTING.md).
