#!/bin/zsh
# Builds unsigned Release .ipa files into .build/ipa for sideloading: Sideloadly on
# iPhone/iPad and atvloadly on Apple TV sign them with a free Apple ID.
# Run from anywhere: Tools/build-ipa.sh
set -euo pipefail
cd "${0:A:h}/.."

out=.build/ipa
rm -rf "$out"
mkdir -p "$out"
xcodegen generate --quiet

for platform sdk in iOS iphoneos tvOS appletvos; do
    xcodebuild build -quiet \
        -project MediaApp.xcodeproj -scheme MediaApp -configuration Release \
        -destination "generic/platform=$platform" -derivedDataPath .build/xcode \
        CODE_SIGNING_ALLOWED=NO

    staging=$(mktemp -d)
    mkdir "$staging/Payload"
    cp -R ".build/xcode/Build/Products/Release-$sdk/Loge.app" "$staging/Payload/"
    (cd "$staging" && zip -qry "$OLDPWD/$out/Loge-$platform.ipa" Payload)
    rm -rf "$staging"
done

ls -lh "$out"
