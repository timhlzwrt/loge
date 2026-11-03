# loge

A private streaming app for my own iPhone, iPad, Apple TV and Mac. Managed Home
shelves, search, title details and IMDb scores work out of the box through
Cinemeta. Add a Stremio playback addon to watch its streams with mpv.
Native SwiftUI, one app target for all
three platforms. Not published anywhere and not meant to be.

Only the bundle ID (`li.tjh.MediaApp`) and Keychain service names keep the old
working name, so saved data and sign-ins carry over between builds.

Home includes festival winner collections and an editorial selection of directors,
using Wikidata's recorded film relationships (which may be incomplete or delayed).
Connect TMDB in Settings with an API Read Access Token to add English movie/series
details, cast portraits, character names and director/writer credits. The token is
validated before being saved in this device's Keychain. Metadata addons remain the
fallback and supply series episodes and IMDb ratings; IMDb playback and saved-list
IDs stay unchanged. Connected actor/director pages use TMDB's full combined movie and TV credits,
with filters, sorting and biographies. Credits without an IMDb mapping stay visible
as information-only titles; IMDb IDs are resolved only when opening a credit.
TMDB responses are cached in bounded device memory; Home preloads the current/next
featured title, and title pages warm the first actor and director. Legacy credits
without a TMDB person ID still fall back to catalog search.
TMDB's required logo and notice appear in Settings → Credits.
Reviews open IMDb's critic links or Letterboxd; review text is not downloaded into the app.

Hold a poster to save it to a custom list. The + button uses Watch Later, preserving
titles saved by older versions. My Lists ends with History: everything played or marked
watched, by day. Audio defaults to English unless changed in Settings.
Intro, recap and credits skipping uses named video chapters, with duration-matched
community timings from [TheIntroDB](https://theintrodb.org/) as a fallback. Community
timings need sufficient confidence and may be unavailable for a title or release.
Only direct HTTP(S) sources play; torrent descriptors, magnet links and `.torrent`
files are rejected. There is no peer-to-peer playback backend.

## Feature to-do

- [ ] Continue Watching in the Apple TV's Top Shelf. On hold: sideloaded with a free Apple ID,
  the extension and its App Group install, but tvOS never launches the extension.
- [ ] Review text in the app. Reviews are links to IMDb and Letterboxd for now; Letterboxd's
  API excludes personal projects, so the text needs another source.
- [ ] Complete festival winner lists. Wikidata's records stop short of the latest editions.
- [ ] Popular Directors ranked by popularity instead of hand-picked, and person pages that
  separate acting from directing.

Not planned: downloads. The interface stays English-only for now.

## Building it

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate              # after adding or removing files
(cd Core && swift test)        # Core unit tests
xcodebuild -project loge.xcodeproj -scheme loge \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode build
```

Swap the destination for `generic/platform=tvOS Simulator` or `platform=macOS`.
CI runs the Core tests and warning-free builds for all three.

`Tools/test-addon.py` serves a local addon at
`http://127.0.0.1:8765/manifest.json` with test streams (MKV, HEVC, multi-track
HLS, header-protected, broken, torrent).

## Getting it onto devices

There's no paid developer account. `Tools/nightly-deploy.sh` installs the latest
`main` every night: on the iPhone over Wi-Fi with Xcode's free Personal Team, and on
the Apple TV through atvloadly, which re-signs it before the seven days run out. Set
it up once with `DEVICE=<udid> Tools/nightly-deploy.sh --install`.
`Tools/build-ipa.sh` writes unsigned `.ipa` files to `.build/ipa` for sideloading by hand.

## What's where

| Path            | What's in it                                                        |
| --------------- | ------------------------------------------------------------------- |
| `Core/`         | `LogeCore` package: addon client, routing, addon and library stores |
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
