#!/bin/zsh
# Builds the Mac app in Release, ad-hoc signed as project.yml sets it up, and packs it into
# .build/dmg/loge-macOS.dmg with a link to Applications to drag it onto. Not notarized, so the
# first launch needs System Settings > Privacy & Security > Open Anyway.
# Run from anywhere: Tools/build-dmg.sh
set -euo pipefail
cd "${0:A:h}/.."

out=.build/dmg
mkdir -p "$out"
xcodegen generate --quiet
xcodebuild build -quiet \
    -project loge.xcodeproj -scheme loge -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath .build/xcode

# dmgbuild writes Finder metadata without AppleScript or an interactive desktop.
# Keep this packaging dependency out of both the app and the system Python.
tools=.build/dmg-tools
if [[ ! -x "$tools/bin/python" ]]; then
    python3 -m venv "$tools"
fi
"$tools/bin/python" -m pip install --quiet 'dmgbuild==1.6.7'
swift -module-cache-path .build/swift-module-cache Tools/render-dmg.swift "$out/background.tiff"
rm -f "$out/loge-macOS.dmg"
"$tools/bin/dmgbuild" -s Tools/dmg-settings.py \
    -D app=.build/xcode/Build/Products/Release/loge.app \
    -D background="$out/background.tiff" loge "$out/loge-macOS.dmg"

ls -lh "$out/loge-macOS.dmg"
