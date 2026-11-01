# Review validation — 31 October 2026

This review used three subagents for addon networking, playback lifecycle and
library/Trakt review, plus a direct review of browsing and simulator behavior.
Existing changes in `AddonModels.swift`, `AGENTS.md` and `Design/` were preserved.
No dependencies were added and no commit was created.

## Automated checks

- Core: `swift test` passed **68 tests in 10 suites**, including eight new
  regressions for URL construction and library/remote progress behavior.
- iOS Simulator, tvOS Simulator and macOS builds passed with
  `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`.
- Xcode emits an App Intents metadata-extraction warning because the app does
  not depend on AppIntents.framework. This is a tooling warning, so these are
  not literally warning-free build logs. No Swift compiler warnings appeared.
- `git diff --check` passed and the complete tracked diff was reviewed.

## Simulator checks

Device coverage: iPhone 18 Pro and iPad Pro 11-inch (M5) on iOS 27.2, and Apple TV
4K (3rd generation) on tvOS 27.0. Tests used Cinemeta and the already-running
repository test addon on loopback. No private stream-addon configuration was
copied into fixtures or documentation.

Six distinct iPhone flows passed across the runs: search results/empty
state/recents, Trakt settings, watched/unwatched episode actions, refresh and
portrait/landscape browsing, failed-source fallback, and the screen tour
(details, source selection, playback and the source sheet). The final rerun
passed all three selected tests: corrected fallback, landscape/refresh and
the strengthened search test. Its landscape screenshot confirms the adjacent
carousel page no longer bleeds into the safe area.

The tvOS `RemoteDriverTests` passed; a second run allowed visual inspection
between right/down/select/menu presses. Screenshots showed focus moving from
the first movie to the second, with the header/backdrop following selection.
This verifies directional focus, not physical Siri Remote swipe gestures.

iPad Home was installed, launched and visually inspected. This was a layout
check, not a full tablet interaction or Picture in Picture test. Mac was built;
its running screens were not inspected during this review.

Screenshots are local validation artifacts in `/tmp/loge-review-shots` and
`/tmp/loge-review-final-shots`, with
additional iPad and tvOS captures in `/tmp/loge-ipad-home.png`,
`/tmp/loge-tv-home.png` and `/tmp/loge-tv-moved-focus.png`. Build/test logs use
the `/tmp/loge-` prefix; Xcode result bundles live under `.build/*/Logs/Test`.
These artifacts are intentionally outside the source diff.

## Limits and follow-ups

- The original fallback UI test successfully started playback, then failed
  while tapping Close after controls auto-hid. It now pauses the short clip
  before taking a screenshot and closing it.
- Search assertions now check that the successful query is actually present
  in recents and the unsuccessful query is absent. Series helpers search
  directly when the title is not visible, avoiding six blind Home swipes.
- Live catalog content and externally hosted test media can change; these UI
  flows are not deterministic offline tests.
- Rapid genre changes and cancellation races were reviewed in code; they have
  no deterministic automated UI regression test in this pass.
- Trakt account authentication/sync was reviewed but not exercised against an
  authenticated account. Remaining lifecycle concerns are listed in the
  [app overview](APP_OVERVIEW.md#follow-up-work).
- The initial review did not test PiP; see the player follow-up below. Hardware
  playback, HDR, Control Center rate display and custom User-Agent transitions
  remain unverified. No performance benchmark was run in the initial review.

## Player follow-up

After a report of iPhone close/PiP failures and off-center controls:

- Transport now has its own centered overlay instead of sharing vertical
  spacers with unequal bars. Title/exit stay at the top; timeline and track
  actions stay at the bottom. Timing controls fit a narrow panel and replace
  the bottom controls while being adjusted.
- PiP waits for successful startup before dismissing the player. Background
  handling preserves video during automatic startup. Synchronous AVKit queries
  use a locked playback snapshot; mutations are dispatched to the main actor
  instead of asserting the callback's thread. Startup failures are visible.
- Session replacement keeps presentation stable and preserves the current
  position. Old PiP callbacks are detached during teardown, and the video host
  is recreated when its player changes. The failure screen can actually open
  the source chooser.
- Short clips offer Up Next only in their last tenth, rather than immediately.
  iOS search fields remain visible, including on iPad.

The iPhone simulator passed three consecutive close/reopen cycles, an actual
in-player source replacement, and centered-control assertions in portrait and
landscape. A further layout run passed timing-panel bounds and confirmed Up
Next stays absent early in a short clip. Screenshots are in
`/tmp/loge-player-fixed` and `/tmp/loge-player-final`.

The iPhone simulator reports PiP unavailable, so that test skipped there. On
iPad, an initial run stopped before playback because search was hidden. After
making the field visible, the complete PiP test passed: button launch,
restoration, Home-triggered automatic PiP and closing the floating window.
Screenshots are in `/tmp/loge-pip-ipad-final`.

The reported after-close failure was not reproduced in the simulator. These
checks do not establish crash-free behavior on the user's physical iPhone.
The user confirmed it quits to the Home Screen. Read-only `devicectl` searches
of the paired iPhone's crash logs returned no Loge or MediaApp reports; a
current device crash report is still needed to identify that exact failure.
Final iPhone timing-layout and search regressions passed, as did the final
tvOS/macOS builds and all 68 Core tests. The Xcode metadata warning remains.

## Performance follow-up

Home's vertical catalog stack is lazy on iOS/Mac, so offscreen rows do not all
start loading when Home opens. A featured title's resume check scans the latest
matching progress entry without rebuilding/sorting Continue Watching. mpv's
per-frame position events no longer recheck the video clock's rate; state and
speed changes still update it.

`Tools/benchmark-resume.swift` compares the previous lookup with the replacement
using 500 synthetic persisted entries and 10,000 queries in an optimized build.
Two runs measured 7.62s versus 0.209s, then 7.41s versus 0.201s; both paths
returned 10,000 matches. That is about 36–37 times faster for this isolated
lookup, not for app startup or playback overall. Build it alongside Core:

```sh
swiftc -swift-version 6 -O -parse-as-library Core/Sources/MediaCore/*.swift Tools/benchmark-resume.swift -o /tmp/loge-performance-benchmark
/tmp/loge-performance-benchmark
```

Before the track-switching follow-up, all 69 Core tests passed, as did iPhone
Home/refresh, player geometry/timing and screen-tour flows, iPad's full PiP
flow, tvOS remote focus and tvOS/macOS builds. Screenshots are in
`/tmp/loge-performance-shots`; logs use `/tmp/loge-performance-`.

Audio/subtitle switches and external subtitle loads now submit async mpv
commands, serialized by completion replies. Manual choices take precedence;
pending choices of the same type are coalesced, and late subtitle downloads
cannot override explicit selection. Track-list events supply the metadata
directly, avoiding repeated synchronous property queries. These changes remove
known blocking work; no claim of lower decoder CPU, higher FPS or a measured
track-switch latency improvement is made without physical-device profiling.

The Apple multi-track HLS fixture intermittently failed opening or stalled after
switching audio. Simulator mpv logs showed TLS errors and corrupt packets.
It is unsuitable as the sole switching regression check. A native AVFoundation
helper now generates a 60-second MOV with English/German audio tracks (distinct
440/660 Hz tones) and looped H.264 video. It downloads only a small public video
when generating; playback and subtitle loading use localhost. No binary media
or new app dependency is checked in. Start both servers for the UI flows:

```sh
python3 Tools/test-addon.py
# In another terminal:
sh Tools/generate-playback-fixture.sh
python3 Tools/test-addon.py --port 8766 --tracks-file /tmp/loge-multiaudio.mov
```

`testTrackSwitchingWhilePlaying` installs the second manifest, changes audio
German → English → German, selects German subtitles → Off → English, checks
that playback remains active and its position advances, then closes playback.
This is functional switching verification, not an audio-quality or latency benchmark.

The iPhone local-fixture switching flow and three close/reopen cycles passed
after the async changes. Screenshots in `/tmp/loge-local-tracks` confirm German
selection and video progress from the start through 24 seconds. On iPad, the
full PiP flow passed again, as did replacing the playing source with the
header-protected fixture (a different URL). Screenshots are in
`/tmp/loge-track-ipad-final`. All 69 Core tests and tvOS/macOS builds passed
again. Xcode's AppIntents metadata warning and the iPad test runner's future
orientation-support warning remain; there were no Swift compiler warnings.
The generator ran end to end and compiles with warnings treated as errors; shell/Python syntax and
the fixture server's 206 byte-range response were also checked.

## Managed discovery and native frame timing

The next branch replaces addon-ordered Home/search with built-in managed
Cinemeta feeds, labels IMDb scores, and adds movie links to Letterboxd on iOS/Mac.
Fresh installs need an addon only for playback. The native video output now
presents at mpv's timed flip instead of enqueuing early; the vendored binary
was rebuilt, not merely patched in source. Automatic choices default to a
50 GB per-episode limit for series using explicit file sizes, with manual choice
for unknown episode sizes and a No limit setting. Movies remain unrestricted.

See [PLAYBACK_PERFORMANCE.md](PLAYBACK_PERFORMANCE.md)
for the latest 78-test, simulator, native-binary, actual 4K fixture and build results.

## Focused cleanup — 1 November 2026

Reviewed playback command submission, browsing cancellation, source-size parsing
and stream caching with three subagents, then reviewed the complete diff. The
cleanup keeps the existing ownership and dependencies: async transport/preview
commands, canceled-response guards, correct binary size units, and one missing
metadata lookup per title per Trakt pull. The stream cache needed no rewrite.

- All 90 Core tests in 13 suites passed, including binary-size conversion and
  cross-unit source ordering (`/tmp/loge-cleanup-core.log`).
- iOS Simulator app/test targets compiled; tvOS Simulator and macOS builds
  succeeded with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`. The existing AppIntents
  metadata-extraction warning remains. Logs: `/tmp/loge-cleanup-ios-final.log`,
  `/tmp/loge-cleanup-tv.log`, `/tmp/loge-cleanup-mac.log`.
- The tvOS remote driver passed after restarting its simulator to restore the
  missing test-manager socket (`/tmp/loge-cleanup-tv-focus-verified.log`). Home
  and focused artwork were visually inspected in `/tmp/loge-cleanup-tv-app.png`.
- The new paused/playing transport regression and existing PiP skip regression
  compiled but did not complete verification. The iPhone simulator was shut down
  during the transport run; a subsequent runner terminated before starting tests.
  The first PiP attempt skipped because its button was absent; the test now waits
  up to ten seconds for availability. These are not counted as passing checks.
  Logs: `/tmp/loge-cleanup-ios-verified.log`, `/tmp/loge-cleanup-ios-final.log`.
- `git diff --check` passed. Physical-device 4K/HDR performance, preview thumbnail
  rendering and live Trakt synchronization were not verified in this follow-up.

The new transport test uses the local 60-second multi-track fixture on port 8766
and checks actual forward/backward position changes while paused, then continued
playback after a playing seek. Rerun it and the PiP skip test when simulator
sessions can remain running for the duration of the checks.
