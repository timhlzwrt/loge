# MPVKit with an AVFoundation video output

[MPVKit](https://github.com/mpvkit/MPVKit) 1.1.0-n9.0.2 (mpv v0.41.0), reduced to its LGPL
product. Every binary comes from MPVKit's releases except `Libmpv.xcframework.zip`, which is
built with the patches in [`patch/`](patch):

- `0004-avfoundation-video-output.patch` adds `vo=avfoundation`, which hands frames to an
  `AVSampleBufferDisplayLayer` (VideoToolbox frames without copying) and can draw subtitles
  into them. That layer is what Picture in Picture, HDR output and the system's own scaling
  work with. It comes from the [streamyfin/MPVKit](https://github.com/streamyfin/MPVKit) fork,
  adapted to mpv 0.41's driver list.
- `0005-avfoundation-fixes.patch` makes it correct for mpv's non-ARC Objective-C build (it
  leaked a Core Image context per file), redraws paused frames so subtitle changes show, and
  leaves three-plane YUV to mpv's converter, since Core Image can't composite subtitles onto it.

To move to a newer MPVKit: update `TAG` in `rebuild-libmpv.sh` and the URLs and checksums in
`Package.swift` from that release's manifest, check the patches still apply, then run
`./rebuild-libmpv.sh`.
