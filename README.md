# Loge

A private media player for my own iPhone, iPad, Apple TV and Mac. It browses
catalogs from Stremio addons, shows details and episodes, lists the streams an
addon offers and plays them with mpv. Native SwiftUI, one app target for all
three platforms. Not published anywhere and not meant to be.

The Xcode project, scheme and bundle ID still use the working name `MediaApp`,
so saved data carries over between builds.

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
