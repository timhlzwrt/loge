#!/bin/zsh
# Builds the Mac app in Release, ad-hoc signed as project.yml sets it up, and packs it into
# .build/dmg/loge-macOS.dmg with a link to Applications to drag it onto. Not notarized, so the
# first launch needs System Settings > Privacy & Security > Open Anyway.
# Run from anywhere: Tools/build-dmg.sh
set -euo pipefail
cd "${0:A:h}/.."

out=.build/dmg
mkdir -p "$out"
rm -f "$out/loge-macOS.dmg"
xcodegen generate --quiet
xcodebuild build -quiet \
    -project loge.xcodeproj -scheme loge -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath .build/xcode

staging=$(mktemp -d)
cp -R .build/xcode/Build/Products/Release/loge.app "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname loge -srcfolder "$staging" -fs HFS+ -format UDZO "$out/loge-macOS.dmg"
rm -rf "$staging"

ls -lh "$out/loge-macOS.dmg"
