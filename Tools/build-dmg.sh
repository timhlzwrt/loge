#!/bin/zsh
# Builds the Mac app in Release and packs it into .build/dmg/loge-macOS.dmg with a link to
# Applications to drag it onto. Not notarized, so the first launch needs System Settings >
# Privacy & Security > Open Anyway.
# With MAC_SIGNING_KEYCHAIN set (the release workflow does), the app is re-signed with loge's
# own certificate from that keychain: an ad-hoc signed app is new to the Keychain with every
# update, which then asks for the password again for each saved sign-in.
# Run from anywhere: Tools/build-dmg.sh
set -euo pipefail
cd "${0:A:h}/.."

out=.build/dmg
mkdir -p "$out"
xcodegen generate --quiet
xcodebuild build -quiet \
    -project loge.xcodeproj -scheme loge -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath .build/xcode
app=.build/xcode/Build/Products/Release/loge.app
if [[ -n "${MAC_SIGNING_KEYCHAIN:-}" ]]; then
    codesign --force --sign "loge Mac signing" --keychain "$MAC_SIGNING_KEYCHAIN" \
        --preserve-metadata=entitlements,flags "$app"
    codesign --verify --deep --strict "$app"
fi

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
    -D app="$app" \
    -D background="$out/background.tiff" loge "$out/loge-macOS.dmg"

ls -lh "$out/loge-macOS.dmg"
