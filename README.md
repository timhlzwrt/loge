# loge

A Stremio addon client for iPhone, iPad, Apple TV and Mac, in native SwiftUI. Browse
catalogs, read details and play streams with mpv.

Movies, series, search and IMDb ratings work out of the box through Cinemeta. To watch
something, add a Stremio addon that provides streams. **loge has no content of its own**:
what plays, and whether you may watch it, depends entirely on the addons you add.

## What it does

- **Home:** popular and Letterboxd lists, genres, festival winners and directors, Continue
  Watching, Watch Later and your own lists.
- **Details:** seasons and episodes with Up Next, cast and crew, reviews, and marking
  things watched. History lists everything you played, by day.
- **Sources:** every stream from your addons, read into resolution, HDR, codec, audio,
  size and bitrate. The best one your connection keeps up with is marked as recommended.
- **Player:** mpv with hardware decoding, HDR, Picture in Picture, AirPlay, subtitles from
  the file, the stream or subtitle addons (with timing adjustment), skipping of intros,
  recaps and credits, and the next episode starting by itself.
- **Accounts, both optional:** [Trakt](https://trakt.tv) syncs progress and history between
  devices; a [TMDB](https://www.themoviedb.org) token adds portraits, filmographies and
  member reviews.

Only direct HTTP(S) streams play. Torrents and magnet links are not supported.

## Installing

loge isn't in the App Store. You sign it yourself with a free Apple ID; no paid developer
account is needed.

### iPhone and iPad: SideStore

1. Set up [SideStore](https://sidestore.io) once, following its guide.
2. In SideStore, open **Sources**, tap **+** and add:

   ```
   https://timhlzwrt.github.io/loge/source.json
   ```

3. Install loge from the source. New builds appear there as updates. SideStore refreshes
   the 7-day signature in the background.

The same source works in [AltStore](https://altstore.io) Classic.

### Apple TV

SideStore doesn't run on tvOS. Download `loge-tvOS.ipa` from the
[latest release](https://github.com/timhlzwrt/loge/releases/latest) and install it with a
computer-based sideloader such as [Sideloadly](https://sideloadly.io). The free signature
lasts 7 days, so reinstall or refresh it each week.

### Mac

Build it from source (below); the Mac build runs ad-hoc signed.

### Which build do I have?

Settings → About shows the build's commit and date, with a link that compares it with the
latest `main` on GitHub. Every push to `main` becomes a
[release](https://github.com/timhlzwrt/loge/releases) numbered by commit count.

## Building

Needs Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate              # after adding or removing files
(cd Core && swift test)        # Core unit tests
xcodebuild -project loge.xcodeproj -scheme loge \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode build
```

Swap the destination for `generic/platform=tvOS Simulator` or `platform=macOS`.
`Tools/build-ipa.sh` writes unsigned `.ipa` files to `.build/ipa`, and
`Tools/test-addon.py` serves a local addon with test streams at
`http://127.0.0.1:8765/manifest.json`.

| Path             | What's in it                                                        |
| ---------------- | ------------------------------------------------------------------- |
| `Core/`          | `LogeCore` package: addon client, routing, addon and library stores |
| `App/Browse/`    | Home, catalog rows, details, sources, search                        |
| `App/Player/`    | mpv player, controls, Picture in Picture, next episode              |
| `App/Settings/`  | Addons, accounts, playback preferences, About                       |
| `Vendor/MPVKit/` | MPVKit with a patched libmpv that adds an AVFoundation video output |
| `Tools/`         | Test addon, `.ipa` builder, device install scripts, icon renderer   |

[The app overview](docs/APP_OVERVIEW.md) covers data flow and platform behaviour, and
[playback performance](docs/PLAYBACK_PERFORMANCE.md) the source size limits and diagnostics.

## Licence

loge is licensed under the [GNU General Public License v3.0](LICENSE).

Playback uses [mpv](https://mpv.io) and [FFmpeg](https://ffmpeg.org) through
[MPVKit](https://github.com/mpvkit/MPVKit)'s LGPL build (1.1.0-n9.0.2, mpv 0.41.0), under
the LGPL. The patches applied to libmpv and the script that rebuilds it from MPVKit's
source are in [`Vendor/MPVKit`](Vendor/MPVKit). Data sources and
image credits are listed in the app under Settings → About → Data Sources. This product uses
the TMDB API but is not endorsed or certified by TMDB.
