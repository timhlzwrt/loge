#!/bin/zsh
# Builds an ad-hoc signed Release Loge.app into .build/dmg/Loge-macOS.dmg. Without a
# developer account it isn't notarized: on first launch, right-click the app and choose Open.
# Run from anywhere: Tools/build-dmg.sh
set -euo pipefail
cd "${0:A:h}/.."

out=.build/dmg
mkdir -p "$out"
rm -f "$out/Loge-macOS.dmg"
xcodegen generate --quiet

xcodebuild build -quiet \
    -project MediaApp.xcodeproj -scheme MediaApp -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath .build/xcode

# The Applications link lets the window double as the install step.
staging=$(mktemp -d)
cp -R .build/xcode/Build/Products/Release/Loge.app "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname Loge -srcfolder "$staging" -format UDZO -ov "$out/Loge-macOS.dmg"
rm -rf "$staging"

ls -lh "$out"
