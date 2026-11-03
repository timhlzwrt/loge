# Playback performance and source sizes

## Automatic source choices

Settings → Playback → Automatic series source limit defaults to **50 GB per episode**.
It applies only to series: remembered-source autoplay, continuing a series,
opening-failure fallbacks, and Up Next. Movies and manual source choices remain
unrestricted, including 4K.
Choose **No limit** to restore automatic choices for sources without file-size metadata.

The cap uses positive `behaviorHints.videoSize` values only. The
[Stremio stream protocol](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/stream.md)
defines that field as the selected video file's size in bytes. A size extracted from
an addon's text may instead describe a torrent or an entire season. It is displayed
but never used to reject an episode as oversized. Explicit pack totals receive a
`pack` suffix and do not outrank individual files merely because they are larger.

When a limit is enabled, unknown-size series sources require a manual choice. A
remembered episode URL therefore waits for fresh source metadata instead of
bypassing the limit. If
no eligible source exists for the next episode, loge does not start one automatically.

File size is not bitrate: duration, variable bitrate, audio tracks and container
overhead differ. The cap is a control over automatic choices, not a claim that every
file below it will play smoothly or that every larger file will stutter.

## Source bitrate and sorting

The source list shows an addon's explicitly reported bitrate in **Mbps**, alongside
file size. It accepts rate units such as `Mbps`, `Mbit/s` and `kbps`; it does not
estimate a rate from runtime or from a season pack's size. Audio-only rate reports
and conflicting rate values are left unknown. These are addon-reported rates,
not measured transfer speeds or promises about peak bitrate.

**Sort & Filter** keeps the 4K, 1080p and 720p groups and sorts within each group.
The default **Cached first** puts known cached sources before unknown cache status,
then uncached sources, preserving addon order for ties. **Lower bitrate**,
**Higher bitrate**, **Smaller file** and **Addon order** are also available. Unknown
rates sort after known rates in either bitrate direction. Pack totals and ambiguous
multiple size reports do not rank as individual video sizes.

The optional **Maximum reported bitrate** filter limits known rates to 10, 25, 50
or 100 Mbps. Unknown rates remain visible, as the list explains; the filter does
not assert that those sources are below the selected limit. It applies to source
choices and automatic fallbacks from this screen, alongside the series-only
automatic file-size policy above. A remembered URL cannot bypass an active bitrate
cap without fresh source metadata.

## Inspect a hitch

During playback, open **Audio → Playback Info** on iPhone, iPad or Mac. On Apple TV,
swipe down to the player panel, then open **Info → Playback Info**. This shows the
decoded dimensions, source frame rate, active hardware decoder, video/audio
bitrates, decoder/output drop counts and buffered seconds. Playback bitrates are
mpv packet-level estimates between keyframes, not network download speed; see the
[mpv properties reference](https://mpv.io/manual/stable/#command-interface-video-bitrate). It requests statistics asynchronously once a second
while the panel is visible; closing it stops polling. It displays no source URLs,
headers or addon configuration.

Use the same file and playback position when comparing results. Note whether drop
counts grow during the hitch, whether the buffer approaches zero, and whether the
problem changes with subtitles enabled. On Apple TV, also check the system's Match
Frame Rate setting; loge already requests the video's display criteria. These mpv
counters do not measure the TV's actual presentation cadence. Simulator playback
cannot verify hardware 4K decode performance, HDR output or HDMI refresh switching.

## Custom video-output timing finding

The pinned mpv 0.41 core calls `draw_frame`, waits for the target presentation time,
then calls `flip_page` ([source, lines 944–952](https://github.com/mpv-player/mpv/blob/v0.41.0/video/out/vo.c#L944-L952)).
Our custom AVFoundation output previously enqueued the sample buffer in `draw_frame`
and marked it `DisplayImmediately`. This presented prepared frames before the core's
timed flip, rather than preserving the target deadline. That was a concrete timing
mismatch and a candidate for cadence jitter.

Patch `0006-avfoundation-presentation-timing.patch` now retains the prepared sample
buffer in `draw_frame`, enqueues it at `flip_page`, and releases pending buffers on
replacement, reset and teardown. Paused subtitle redraws also use the draw/flip path.
The vendored ZIP was rebuilt for all nine architectures across iOS, tvOS, their
simulators and macOS. Its supported platform/architecture sets match the original.
Physical-device testing is still needed to quantify 4K improvement and determine
whether a particular source also has network, decoder or display-cadence issues.

VideoToolbox hardware decoding remains enabled. Subtitle compositing already avoids
the Core Image render when no subtitle is visible. Cache limits and decode settings
remain unchanged until measurements identify a bottleneck.

## Reproduce the local 4K check

Generate the baseline multi-audio movie, then upscale a 20-second segment and
encode it as actual 3840 × 2160 HEVC at 30 fps. This is synthetic test media,
not an image-quality comparison. Nothing binary is checked into the repository.

```sh
sh Tools/generate-playback-fixture.sh
swiftc -parse-as-library Tools/generate-4k-fixture.swift -o /tmp/loge-generate-4k
/tmp/loge-generate-4k
python3 Tools/test-addon.py --port 8768 --tracks-file /tmp/loge-4k.mov --name '4K Playback Test'
```

`FlowTests.test4KPlaybackAdvances` installs the local manifest, plays the file,
checks the decoded dimensions in Playback Info, verifies position advancement
and closes playback. Language-switching tests use the separate 60-second
baseline fixture server on port 8766. The normal test addon can run on another
port using `--port`; pass its manifest URL through
`TEST_RUNNER_PLAYBACK_TEST_ADDON_URL` when running UI tests.

## Validation, 31 October–1 November 2026

- All 78 Core tests passed, including discovery defaults/migration, series-only
  file-size limits, unrestricted large/unknown-size movies, package totals and
  unknown-size episode handling.
- The existing Settings UI flow passed on iPad after the series-only change.
  Its screenshot confirms the per-episode value and unrestricted-movie wording
  fit without truncation (`/tmp/loge-series-only-settings/settings-trakt.png`).
- All three app platforms built with Swift warnings treated as errors. The
  vendored native binary was rebuilt for nine architectures, preserving its
  five platform slice sets. The extracted iOS simulator artifact's SHA256
  matched the rebuilt ZIP before tests ran.
- A clean iPhone simulator with no installed addons passed managed Home,
  search, IMDb score/Letterboxd-link checks, refresh and landscape layouts.
- With the rebuilt player, actual 4K playback advanced and closed successfully.
  The captured stats showed VideoToolbox, zero decoder/output drops and 15.7 s
  buffered. This is one simulator observation, not a physical-device benchmark.
- Language/subtitle changes during playback, playback diagnostics, centred
  portrait/landscape transport, timing-panel bounds, and three close/reopen
  cycles passed. The close test uses a separate title so longer synthetic
  media does not leave incompatible resume timestamps for the short fixture.
- Apple TV remote right/down/select/menu navigation passed; screenshots were
  inspected. This does not test physical Siri Remote swipes or HDMI timing.
- The rebuilt player passed iPad PiP startup/restoration, automatic PiP on Home
  and floating-window close, followed by the managed Home/details screen tour.
  Screenshots are in `/tmp/loge-managed-ipad-final`.

The first 4K assertion expected a standalone value but iOS combines it into
the accessible label `Video, 3840 × 2160`; the assertion was corrected. Earlier
close checks mixed fixtures with different durations under the same title;
the close regression now isolates its watch history. No production behavior
was changed merely to make these assertions pass.

Screenshots are under `/tmp/loge-discovery-shots`, `/tmp/loge-rebuilt-player`,
`/tmp/loge-rebuilt-final`, `/tmp/loge-close-final` and
`/tmp/loge-managed-tv-home-final.png`; logs use `/tmp/loge-` and Xcode result
bundles remain under `.build/*/Logs/Test`. Xcode's existing AppIntents metadata
notice remains; the native dependency build also reports an existing deprecated
Core Video attachment API. Hardware 4K frame pacing, HDR and HDMI refresh
matching still need real-device verification.

## Picture in Picture skipping

PiP's play/pause state follows mpv's explicit pause state, not `paused-for-cache`.
A seek can briefly buffer while the user's intent remains playing. The display
clock still stops during buffering, without reporting a user pause to AVKit.

PiP skips use asynchronous relative seeks and finish on mpv's
`MPV_EVENT_PLAYBACK_RESTART`, after refreshing the position and PiP's cached
playback state. Multiple requests run in order. Pending completion handlers are
also released on a failed file, source replacement or player shutdown. A 15-second
safety timeout releases controls if a demuxer silently rejects a queued seek
without a restart event; it does not force playback to resume. Relative
seeks retain mpv's fast keyframe behavior rather than forcing an exact decode.

Apple requires the seek to finish and the timebase to reflect playback before
calling the [skip completion handler](https://developer.apple.com/documentation/avkit/avpictureinpicturesamplebufferplaybackdelegate/pictureinpicturecontroller(_:skipbyinterval:completion:)).
The [mpv client API](https://github.com/mpv-player/mpv/blob/v0.41.0/include/mpv/client.h)
identifies `PLAYBACK_RESTART` as the event for detecting seek completion.

## Follow-up validation, 1 November 2026

- All 89 current Core tests passed, including reported bitrate units, audio-only
  and conflicting rate reports, cache ordering, unknown rates and series-only
  automatic file-size limits.
- iOS, tvOS and macOS compiled with Swift warnings treated as errors. Existing
  AppIntents metadata and UI-runner orientation notices remain.
- The iPad PiP regression passed: skipping a paused video moved its position
  without starting playback; forward/backward/forward skips while playing kept
  playback advancing after restoring. The player then closed normally.
- The iPhone source flow passed bitrate display, lower-bitrate sorting, a 25 Mbps
  cap (25.2 Mbps hidden, 23.6 Mbps retained), and clearing the cap. Screenshots
  in `/tmp/loge-source-bitrate-verified` were inspected; unknown rates remain visible.
- Apple TV source focus, opening the Sort & Filter menu, selecting a sort and
  bitrate cap, and returning with Menu were checked with the remote driver.
  Screenshots use `/tmp/loge-bitrate-tv-*.png`.
- Playback Info was inspected after the skips. The fixture reported audio at
  768 kbps; video bitrate was unavailable immediately after seeking. mpv may
  need another keyframe interval to produce a new video estimate.

PiP screenshots are in `/tmp/loge-pip-skip-verified`; the successful run is
`/tmp/loge-pip-skip-verified.log`. The first test attempt hit an auto-hide race
before reaching PiP; the test now confirms a paused state before seeking.
Shared build contention and idle iOS 27.0 simulator background services delayed
execution; no other build was stopped.
