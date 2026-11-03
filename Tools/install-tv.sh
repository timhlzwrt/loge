#!/bin/zsh
# Builds the tvOS .ipa and hands it to atvloadly, which signs it with the free Apple ID signed in
# there, installs it on the paired Apple TV and re-signs it every night before the 7 days run out.
# atvloadly runs on the home server (CT 107); pairing and the Apple ID sign-in happen once in its
# web UI. Needs the home network or VPN.
# Run from anywhere: Tools/install-tv.sh
# ATVLOADLY=<url> overrides the server, IPA=<path> installs an existing .ipa without building.
set -euo pipefail
cd "${0:A:h}/.."

server=${ATVLOADLY:-http://192.168.178.115:5533}

api() {
    local response
    response=$(curl -fsS --max-time 600 "$@")
    if [[ $(jq -r .code <<<"$response") != 200 ]]; then
        echo "atvloadly: $(jq -r .msg <<<"$response")" >&2
        return 1
    fi
    jq .data <<<"$response"
}

# Fail before a several-minute build if the server, account or Apple TV is missing.
accounts=$(api "$server/api/accounts")
if [[ $(jq length <<<"$accounts") != 1 ]]; then
    echo "atvloadly needs exactly one Apple ID; sign in at $server." >&2
    exit 1
fi
account=$(jq -r 'keys[0]' <<<"$accounts")
tvs=$(api "$server/api/devices" | jq '[.[] | select(.device_class == "AppleTV")] | length')
if [[ $tvs == 0 ]]; then
    echo "No Apple TV paired in atvloadly; pair it at $server." >&2
    exit 1
fi

ipa=${IPA:-.build/ipa/loge-tvOS.ipa}
[[ -n ${IPA:-} ]] || Tools/build-ipa.sh tvOS

# atvloadly keeps one record per app and device; it changes when the install finishes.
bundle_id=$(unzip -p "$ipa" 'Payload/*.app/Info.plist' | plutil -extract CFBundleIdentifier raw -)
record='[.[] | select(.device_class == "AppleTV" and .bundle_identifier == $id)] | first'
before=$(api "$server/api/apps" | jq -c --arg id "$bundle_id" "$record")

echo "Uploading $(du -h "$ipa" | cut -f1) to $server…"
api -F "file=@$ipa" -F "account=$account" "$server/api/install" | jq -r '"Installing on \(.device)…"'

for _ in {1..120}; do
    sleep 5
    installing=$(api "$server/api/apps/installing" | jq length)
    [[ $installing == 0 ]] && break
done

after=$(api "$server/api/apps" | jq -c --arg id "$bundle_id" "$record")
# A failed install only leaves its reason in the log.
if [[ $after == null || $after == "$before" ]]; then
    echo "The install failed or did not finish; atvloadly's log at $server says why." >&2
    exit 1
fi
if [[ $(jq .refreshed_result <<<"$after") != true ]]; then
    echo "Install failed: $(jq -c .refreshed_error <<<"$after")" >&2
    exit 1
fi
jq -r '"Installed loge \(.version) on \(.device), valid until \(.expiration_date[:16])."' <<<"$after"
