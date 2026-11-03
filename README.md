# Loge

A private streaming app for my own iPhone, iPad, Apple TV and Mac. Managed Home
shelves, search, title details and IMDb scores work out of the box through
Cinemeta. Add a Stremio playback addon to watch its streams with mpv.
Native SwiftUI, one app target for all
three platforms. Not published anywhere and not meant to be.

The Xcode project, scheme and bundle ID still use the working name `MediaApp`,
so saved data carries over between builds.

Home includes festival winner collections and an editorial selection of directors,
using Wikidata's recorded film relationships (which may be incomplete or delayed).
Connect TMDB in Settings with an API Read Access Token to add English movie/series
details, cast portraits, character names and director/writer credits. The token is
validated before being saved in this device's Keychain. Metadata addons remain the
fallback and supply series episodes and IMDb ratings; IMDb playback and saved-list
IDs stay unchanged. Person title lists still use catalog search and may be incomplete.
TMDB's required logo and notice appear in Settings → Credits.
Reviews open IMDb's critic links or Letterboxd; review text is not downloaded into the app.

Hold a poster to save it to a custom list. The + button uses Watch Later, preserving
titles saved by older versions. Audio defaults to English unless changed in Settings.
Intro, recap and credits skipping uses named video chapters, with duration-matched
community timings from [TheIntroDB](https://theintrodb.org/) as a fallback. Community
timings need sufficient confidence and may be unavailable for a title or release.
Only direct HTTP(S) sources play; torrent descriptors, magnet links and `.torrent`
files are rejected. There is no peer-to-peer playback backend.

## Building it

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate              # after adding or removing files
(cd Core && swift test)        # Core unit tests
xcodebuild -project MediaApp.xcodeproj -scheme MediaApp \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode build
```

Swap the destination for `generic/platform=tvOS Simulator` or `platform=macOS`.
CI runs the Core tests and warning-free builds for all three.

`Tools/test-addon.py` serves a local addon at
`http://127.0.0.1:8765/manifest.json` with test streams (MKV, HEVC, multi-track
HLS, header-protected, broken, torrent).

## Getting it onto devices

There's no paid developer account. `Tools/build-ipa.sh` writes unsigned `.ipa`
files to `.build/ipa`; Sideloadly (iPhone/iPad) and atvloadly (Apple TV) sign
them with a free Apple ID and refresh them before the seven days run out.

## What's where

| Path            | What's in it                                                        |
| --------------- | ------------------------------------------------------------------- |
| `Core/`         | `MediaCore` package: addon client, routing, addon and library stores |
| `App/Browse/`   | Home, catalog rows, details, sources, search                        |
| `App/Player/`   | mpv player, controls, next-episode countdown                        |
| `App/Settings/` | Addons and playback language preferences                            |
| `Vendor/MPVKit/`| MPVKit with a patched libmpv that follows layer resizes             |
| `Tools/`        | Test addon, icon renderer, `.ipa` builder                           |

mpv comes through MPVKit's LGPL build.

## Implementation notes

See [the app overview](docs/APP_OVERVIEW.md) for ownership, data flow,
platform behavior, persistence, review fixes and follow-up work, and
[review validation](docs/REVIEW_VALIDATION.md) for checks actually performed.
See [playback performance](docs/PLAYBACK_PERFORMANCE.md) for the automatic source
size limit, on-screen diagnostics and native frame-presentation correction.
