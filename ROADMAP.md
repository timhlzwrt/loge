# Roadmap

[Back to loge](README.md)

**Status: pre-1.0.** This is a small, actively developed client. The priorities
are reliable playback and clear cross-device behavior—not a list of promised
release dates. This roadmap reflects the source as of **7 November 2026**.

## Shipped

- [x] Native iPhone, iPad, Apple TV and Mac browsing and playback.
- [x] Built-in Cinemeta discovery/search, genre shelves, festival editions,
  director discovery and optional TMDB metadata, filmographies and reviews.
- [x] Addon management, structured source selection, remembered sources,
  connection-aware recommendations and automatic fallback.
- [x] mpv playback, subtitles and timing controls, timeline previews,
  available chapter/community skips and automatic next episodes.
- [x] Continue Watching, episode resume, Up Next, Watch Later, custom lists
  and day-grouped viewing history.
- [x] Trakt device-code sign-in, scrobbling, paused-progress import and
  watched/unwatched updates.
- [x] Optional encrypted self-hosted accounts with progress, watched state,
  addons and preferences; offline merging and explicit conflict resolution.
- [x] Scoped shared setups, separate private progress, expiring invitations,
  device revocation and a local service administration page.
- [x] GitHub release assets for iOS/tvOS/Mac, a SideStore source, a Mac
  drag-to-Applications installer and signed Sparkle updates.

“Shipped” means implemented in the code, not validated on every hardware or
provider combination. The current gaps are below.

## Next: verification first

### 1. Confirm the supported OS floor

- [ ] Launch the corrected **OS 26** builds on iPhone/iPad, Apple TV and Mac.
- [ ] Exercise browse → details → sources → playback, pause/resume, relaunch
  and settings on those minimum versions.
- [ ] Check the packaged Release builds and update feeds advertise the same
  minimums as the app and LogeCore.

OS 26 API-availability builds already pass on all targets. That is a build
check, not a substitute for minimum-version runtime testing.

### 2. Close the hardware playback gaps

- [ ] Apple TV: confirm Siri Remote swipe-to-scrub, thumbnail behavior,
  focus while skipping, and the Home scrolling changes on a physical device.
- [ ] Apple TV: check HDR/dynamic-range and frame-rate matching with an
  appropriate television, source and display settings.
- [ ] Mac: exercise full playback, Picture in Picture and long addon source
  names—not just browsing and settings.
- [ ] Record PiP, AirPlay and HDR results by device/output combination.
  Simulator checks alone cannot validate these.

iPhone hardware playback and PiP regression checks have passed previously;
that does not establish Apple TV or Mac parity.

### 3. Validate real cross-device handoff

- [ ] Complete physical iPhone ↔ Apple TV handoff in both directions using
  the same self-hosted account, including episode and position accuracy.
- [ ] Repeat Trakt-only handoff with the live API, including reconnect,
  sign-out and newer local progress versus remote progress.
- [ ] Test interruption/offline recovery without losing rewatches,
  backward seeks, completions or explicit progress removals.

Independent-store tests and disposable-account live sync checks exist. They
do not replace a physical two-device playback session.

## On hold

**Apple TV Top Shelf.** An earlier extension could be signed and installed
through the sideloading setup, but tvOS did not launch it. Investigate the
physical device's system logs before building more extension code. There is
no Top Shelf support in the shipped app.

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
