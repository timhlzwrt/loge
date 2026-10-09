#!/bin/zsh
# Rebuilds Libmpv.xcframework.zip with patch/*.patch applied on top of MPVKit's own patches.
# Needs: brew install meson ninja pkg-config nasm cmake autoconf automake
# Takes about an hour; FFmpeg and mpv are compiled, every other library is downloaded.
set -euo pipefail

TAG=1.1.0-n9.0.2  # Keep in step with the URLs in Package.swift.
HERE=${0:A:h}
WORK=$(mktemp -d)

git clone --depth 1 --branch $TAG https://github.com/mpvkit/MPVKit "$WORK/MPVKit"
cp "$HERE"/patch/*.patch "$WORK/MPVKit/Sources/BuildScripts/patch/libmpv/"
(cd "$WORK/MPVKit" && make build platform=ios,tvos,macos)

cp "$WORK/MPVKit/dist/release/Libmpv.xcframework.zip" "$HERE/"
rm -rf "$WORK"
echo "Wrote $HERE/Libmpv.xcframework.zip"
