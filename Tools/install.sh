#!/bin/zsh
# Builds loge and installs it on your own devices: an iPhone or iPad that Xcode can reach,
# signed with the free Personal Team from Xcode > Settings > Accounts, and the Apple TV through
# atvloadly, which signs with the Apple ID signed in there and re-signs every night before the
# 7 days run out (it runs on a server on the home network; pair and sign in once in its web UI).
#
# Run from anywhere: Tools/install.sh [--here] [--debug] [--launch | --console] [phone | tv | all]
#   Without a device, a menu lists the reachable iPhones and iPads, the Apple TV and All;
#   phone picks the first reachable iPhone or iPad.
#   By default it builds Release of origin/main in a checkout of its own (.build/install), so
#   work in progress here is never touched; --here builds this checkout as it is.
#   --debug builds Debug for an iPhone or iPad from this checkout (implies --here).
#   --launch starts the app on an iPhone or iPad afterwards, --console also streams its output.
#   TEAM=<team id> overrides the Xcode team, ATVLOADLY=<url> the atvloadly server.
set -euo pipefail

usage="Usage: Tools/install.sh [--here] [--debug] [--launch | --console] [phone | tv | all]"
here= configuration=Release target=
launch=()
for argument; do
    case $argument in
        --here) here=1 ;;
        --debug) here=1 configuration=Debug ;;
        --launch) launch=(--terminate-existing) ;;
        --console) launch=(--terminate-existing --console) ;;
        phone|tv|all) target=$argument ;;
        *) echo $usage >&2; exit 1 ;;
    esac
done

repo=$(git -C "${0:A:h}" rev-parse --path-format=absolute --git-common-dir)
if [[ -n $here ]]; then
    cd "${0:A:h:h}"
    echo "Installing this checkout ($configuration)."
else
    checkout=${repo:h}/.build/install
    git -C "$repo" fetch --quiet origin main
    head=$(git -C "$repo" rev-parse origin/main)
    [[ -d $checkout ]] || git -C "$repo" worktree add --quiet --detach "$checkout" "$head"
    git -C "$checkout" checkout --quiet --force --detach "$head"
    cd "$checkout"
    echo "Installing ${head:0:7} of main."
fi

# iPhones and iPads Xcode can reach now, as "udid<tab>name".
list=$(mktemp)
trap 'rm -f "$list"' EXIT
xcrun devicectl list devices --quiet --json-output "$list"
phones=("${(@f)$(python3 -I -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw = d["hardwareProperties"]
    if hw.get("reality") == "physical" and hw.get("platform") == "iOS" \
            and d["connectionProperties"].get("tunnelState") != "unavailable":
        print(hw["udid"] + "\t" + d["deviceProperties"]["name"])
' "$list")}")
phones=(${phones:#})

install_phone() {
    local udid=${1%%$'\t'*} name=${1#*$'\t'}
    echo "== $name"
    local team=${TEAM:-$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
        | sed -n 's/.*teamID = \(.*\);/\1/p' | head -1)}
    if [[ -z $team ]]; then
        echo "No team found: sign in with your Apple ID in Xcode > Settings > Accounts." >&2
        return 1
    fi
    xcodegen generate --quiet
    xcodebuild build -quiet \
        -project loge.xcodeproj -scheme loge -configuration "$configuration" \
        -destination "id=$udid" -derivedDataPath .build/xcode \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
        CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$team" || return 1
    xcrun devicectl device install app --device "$udid" \
        ".build/xcode/Build/Products/$configuration-iphoneos/loge.app" || return 1
    # Only on request: a locked phone refuses to launch, which would read as a failed install.
    (( $#launch )) || return 0
    xcrun devicectl device process launch --device "$udid" $launch li.tjh.loge
}

atvloadly() {
    local response
    response=$(curl -fsS --max-time 600 "$@") || return 1
    if [[ $(jq -r .code <<<"$response") != 200 ]]; then
        echo "atvloadly: $(jq -r .msg <<<"$response")" >&2
        return 1
    fi
    jq .data <<<"$response"
}

install_tv() {
    echo "== Apple TV"
    local server=${ATVLOADLY:-http://192.168.178.115:5533}
    # Fail before a several-minute build if the server, account or Apple TV is missing.
    local accounts
    accounts=$(atvloadly "$server/api/accounts") || return 1
    if [[ $(jq length <<<"$accounts") != 1 ]]; then
        echo "atvloadly needs exactly one Apple ID; sign in at $server." >&2
        return 1
    fi
    local account=$(jq -r 'keys[0]' <<<"$accounts") tvs
    tvs=$(atvloadly "$server/api/devices" | jq '[.[] | select(.device_class == "AppleTV")] | length') || return 1
    if [[ $tvs == 0 ]]; then
        echo "No Apple TV paired in atvloadly; pair it at $server." >&2
        return 1
    fi

    Tools/build-ipa.sh tvOS || return 1
    local ipa=.build/ipa/loge-tvOS.ipa
    # atvloadly keeps one record per app and device; it changes when the install finishes.
    local bundle_id=$(unzip -p "$ipa" 'Payload/*.app/Info.plist' | plutil -extract CFBundleIdentifier raw -)
    local record='[.[] | select(.device_class == "AppleTV" and .bundle_identifier == $id)] | first'
    local before after
    before=$(atvloadly "$server/api/apps" | jq -c --arg id "$bundle_id" "$record") || return 1

    echo "Uploading $(du -h "$ipa" | cut -f1) to $server…"
    atvloadly -F "file=@$ipa" -F "account=$account" "$server/api/install" \
        | jq -r '"Installing on \(.device)…"' || return 1
    for _ in {1..120}; do
        sleep 5
        [[ $(atvloadly "$server/api/apps/installing" | jq length) == 0 ]] && break
    done

    after=$(atvloadly "$server/api/apps" | jq -c --arg id "$bundle_id" "$record") || return 1
    # A failed install only leaves its reason in the log.
    if [[ $after == null || $after == "$before" ]]; then
        echo "The install failed or did not finish; atvloadly's log at $server says why." >&2
        return 1
    fi
    if [[ $(jq .refreshed_result <<<"$after") != true ]]; then
        echo "Install failed: $(jq -c .refreshed_error <<<"$after")" >&2
        return 1
    fi
    jq -r '"Installed loge \(.version) on \(.device), valid until \(.expiration_date[:16])."' <<<"$after"
}

if [[ -z $target ]]; then
    choices=()
    for phone in $phones; do choices+=("${phone#*$'\t'}"); done
    choices+=("Apple TV" "All")
    PS3="Choose a number: "
    choice=
    select choice in $choices; do
        [[ -n $choice ]] && break
    done
    case $choice in
        "") exit 1 ;;
        "Apple TV") target=tv ;;
        All) target=all ;;
        *) target=phone
           phones=("${phones[$REPLY]}") ;;
    esac
fi

if [[ $target != tv ]] && (( ! $#phones )); then
    echo "No iPhone or iPad reachable." >&2
    [[ $target == phone ]] && exit 1
fi

failed=()
case $target in
    phone) install_phone "$phones[1]" || failed+=("${phones[1]#*$'\t'}") ;;
    tv) install_tv || failed+=("Apple TV") ;;
    all)
        for phone in $phones; do install_phone "$phone" || failed+=("${phone#*$'\t'}"); done
        install_tv || failed+=("Apple TV")
        ;;
esac

if (( $#failed )); then
    echo "Failed on ${(j: and :)failed}." >&2
    exit 1
fi
