# Roadmap

[Back to loge](README.md)

**Status: pre-1.0.** This is a small, actively developed client. The priorities
are reliable playback and clear cross-device behavior—not a list of promised
release dates. This roadmap reflects the source as of **12 November 2026**.

## Shipped

- [x] Native iPhone, iPad, Apple TV and Mac browsing and playback.
- [x] Built-in Cinemeta discovery/search, genre shelves and optional TMDB
  metadata and filmographies.
- [x] TMDB-based recommendations: More Like This on details and a Recommended
  Home row ranked on the device from watched and saved titles.
- [x] Addon management, structured source selection, remembered sources,
  connection-aware recommendations and automatic fallback.
- [x] A source filter by audio language, HDR and bitrate (not codec), and a maximum
  bitrate for automatic choices that replaced the per-episode size limit.
- [x] mpv playback, subtitles and timing controls, timeline previews,
  available chapter/community skips and automatic next episodes.
- [x] Continue Watching, episode resume, Up Next and Watch Later (custom lists
  were folded into it in November 2026), and Recently Watched in My Lists (the last
  12 titles finished, replacing the History page).
- [x] New episodes of followed series in Continue Watching, trailers opened on YouTube (not on Apple TV), and the other films of a film series
  on a movie's page (TMDB).
- [x] Arranged Home shelves (Settings → Home): hide, reorder, add installed addons'
  catalogs and reset, synced with the account's setup.
- [x] Optional encrypted self-hosted accounts with progress, watched state,
  addons and preferences; offline merging, the newest position winning, and a
  choice when a title was removed on one device and played on another.
- [x] Expiring device invitations, device revocation and a local service
  administration page.
- [x] A one-time setup copy (addons, optionally playback preferences) as a link
  or code, replacing the live shared setups of earlier versions.
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
  progress, explicit removals and sign-out. Exercise account connection and setup
  copy UI in simulators. No physical phone-to-TV handoff or live-provider check is a
  release prerequisite.
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

### 1. Sync Watch Later

Playback progress and setup already sync through the optional self-hosted account;
Watch Later should be considered separately. Carry its titles and deliberate removals
between a person's devices, with defined offline-merge rules. Keep it private to the
account, not part of a setup copy.
This would expand sync scope and needs agreement before implementation.

**Test target:** independent stores converge after concurrent additions and
removals; reconnect doesn't resurrect deleted entries; another account can't read them.

### 2. Search installed addons

Search currently uses the built-in movie and series feeds. Offer opt-in search of
installed catalogs that advertise search support, preserving addon order and showing
results as each provider responds. A slow or failing addon must not block other results.
Keep built-in search as the default to avoid sending every query to every provider.

**Test target:** fixture addons cover partial failure, delayed responses, duplicate
titles and changing the query before earlier responses finish.

## On hold

**Apple TV Top Shelf.** An earlier extension could be signed and installed
through the sideloading setup, but tvOS did not launch it. Further investigation
depends on physical device logs and behavior, so it isn't planned. There is no
Top Shelf support in the shipped app.

**More scrolling/image-cache work.** Profile image decoding and long catalog
scrolls first. Keep measured regressions separate from speculative rewrites.

## Not in scope

- Offline downloads, a torrent engine or built-in content hosting.
- A default hosted sync backend or iCloud sync. Trakt was supported until
  November 2026 and removed in favour of the self-hosted account.
- Scores beyond IMDb's. Letterboxd and Rotten Tomatoes scores came from the user's own
  MDBList key until November 2026; they were removed, and the saved key is deleted at launch.
- Promised App Store distribution, notarization or Intel Mac support.
- A server-side recommendation engine (recommendations are ranked on the device
  from TMDB's suggestions) or Letterboxd account integration.
- Interface localization is not scheduled; the UI is currently English.

Watch Later/custom-list sync is **not implemented**. Any expansion of the
current sync contract needs an explicit scope decision, not an unchecked
feature claim.

## Help move this forward

Useful contributions include reproducible bugs, focused fixes, and test results
that identify the **device, OS, build commit and exact scenario**. Propose new
features through the [issue forms](https://github.com/timhlzwrt/loge/issues/new/choose)
before starting a broad implementation. See [Contributing](CONTRIBUTING.md).
