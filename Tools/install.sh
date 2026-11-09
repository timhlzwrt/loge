#!/bin/zsh
# Installs the latest main on a device over Wi-Fi, picked from a menu: an iPhone or iPad paired
# with Xcode (Tools/run-device.sh, free Personal Team), the Apple TV through atvloadly
# (Tools/install-tv.sh), or all of them. Builds Release in a checkout of its own, so work in
# progress here is never touched.
# Run from anywhere: Tools/install.sh [--here]
#   --here installs this checkout as it is instead of origin/main.
set -euo pipefail

repo=$(git -C "${0:A:h}" rev-parse --path-format=absolute --git-common-dir)
checkout=${repo:h}/.build/install

if [[ ${1:-} == --here ]]; then
    checkout=${0:A:h:h}
    head=
elif [[ -n ${1:-} ]]; then
    echo "Usage: Tools/install.sh [--here]" >&2
    exit 1
else
    git -C "$repo" fetch --quiet origin main
    head=$(git -C "$repo" rev-parse origin/main)
    [[ -d $checkout ]] || git -C "$repo" worktree add --quiet --detach "$checkout" "$head"
    git -C "$checkout" checkout --quiet --force --detach "$head"
fi
cd "$checkout"

# iPhones and iPads Xcode can reach now, by name.
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

choices=()
for phone in $phones; do choices+=("${phone#*$'\t'}"); done
choices+=("Apple TV" "All")

echo "Install ${${head:+${head:0:7} of main}:-this checkout} on:"
PS3="Choose a number: "
choice=
select choice in $choices; do
    [[ -n $choice ]] && break
done
[[ -n $choice ]] || exit 1

failed=()

install_phone() {
    local udid=${1%%$'\t'*} name=${1#*$'\t'}
    echo "== $name"
    # Not launched: a locked phone refuses, which would read as a failed install.
    DEVICE=$udid CONFIGURATION=Release Tools/run-device.sh --no-launch || failed+=("$name")
}

install_tv() {
    echo "== Apple TV"
    Tools/install-tv.sh || failed+=("Apple TV")
}

case $choice in
    "Apple TV") install_tv ;;
    All)
        for phone in $phones; do install_phone "$phone"; done
        install_tv
        ;;
    *) install_phone "${phones[$REPLY]}" ;;
esac

if (( $#failed )); then
    echo "Failed on ${(j: and :)failed}." >&2
    exit 1
fi
