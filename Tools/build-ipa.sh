#!/bin/zsh
# Builds unsigned Release .ipa files into .build/ipa for sideloading: Sideloadly on
# iPhone/iPad and atvloadly on Apple TV sign them with a free Apple ID.
# Run from anywhere: Tools/build-ipa.sh [iOS|tvOS]   (both without an argument)
set -euo pipefail
cd "${0:A:h}/.."

typeset -A sdks=(iOS iphoneos tvOS appletvos)
platforms=(${@:-iOS tvOS})
for platform in $platforms; do
    if [[ -z ${sdks[$platform]:-} ]]; then
        echo "Unknown platform $platform; use iOS or tvOS." >&2
        exit 1
    fi
done

out=.build/ipa
mkdir -p "$out"
xcodegen generate --quiet

for platform in $platforms; do
    sdk=${sdks[$platform]}
    rm -f "$out/Loge-$platform.ipa"
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
