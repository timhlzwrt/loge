# MPVKit with a resize patch

[MPVKit](https://github.com/mpvkit/MPVKit) 1.1.0-n9.0.2 (mpv v0.41.0), reduced to its LGPL
product. Every binary comes from MPVKit's releases except `Libmpv.xcframework.zip`, which is
built with [`patch/0004-moltenvk-resize.patch`](patch/0004-moltenvk-resize.patch).

MPVKit's MoltenVK context reads the layer's size only when the video is configured, so after
a rotation or window resize mpv kept drawing for the old size. The patch has it compare the
layer's drawable size with its own on every video-thread iteration and resize when they differ,
and observe the layer's `drawableSize` to wake that thread, which otherwise sleeps while paused.
mpv's macOS context handles its window the same way.

To move to a newer MPVKit: update `TAG` in `rebuild-libmpv.sh` and the URLs and checksums in
`Package.swift` from that release's manifest, check the patch still applies, then run
`./rebuild-libmpv.sh`.
