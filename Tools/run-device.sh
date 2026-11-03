#!/bin/zsh
# Builds a Debug build, installs it on the connected iPhone/iPad and launches it.
# Signs with the free Personal Team from Xcode > Settings > Accounts, so no paid account;
# the install stops launching after 7 days, rerun to refresh it.
# Run from anywhere: Tools/run-device.sh [--console | --no-launch]   (--console streams the app's
# output, --no-launch only installs). DEVICE=<udid> and TEAM=<team id> override the automatic
# picks; CONFIGURATION=Release builds the everyday version.
set -euo pipefail
cd "${0:A:h}/.."
configuration=${CONFIGURATION:-Debug}

team=${TEAM:-$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | sed -n 's/.*teamID = \(.*\);/\1/p' | head -1)}
if [[ -z $team ]]; then
    echo "No team found: sign in with your Apple ID in Xcode > Settings > Accounts." >&2
    exit 1
fi

devices=$(mktemp)
trap 'rm -f "$devices"' EXIT
xcrun devicectl list devices --quiet --json-output "$devices"
device=${DEVICE:-$(python3 -I -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw = d["hardwareProperties"]
    if hw.get("reality") == "physical" and hw.get("platform") == "iOS" \
            and d["connectionProperties"].get("tunnelState") != "unavailable":
        print(hw["udid"]); break
' "$devices")}
if [[ -z $device ]]; then
    echo "No iPhone or iPad connected." >&2
    exit 1
fi

xcodegen generate --quiet
xcodebuild build -quiet \
    -project loge.xcodeproj -scheme loge -configuration "$configuration" \
    -destination "id=$device" -derivedDataPath .build/xcode \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$team"

app=.build/xcode/Build/Products/$configuration-iphoneos/loge.app
xcrun devicectl device install app --device "$device" "$app"
[[ ${1:-} == --no-launch ]] && exit 0
launch=(--terminate-existing)
[[ ${1:-} == --console ]] && launch+=(--console)
xcrun devicectl device process launch --device "$device" $launch li.tjh.MediaApp
