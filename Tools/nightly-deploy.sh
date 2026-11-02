#!/bin/zsh
# Keeps the devices on the latest main without anyone at the keyboard. A launchd job runs this
# every night: it moves its own checkout to origin/main and, when main changed since the last
# install, installs a Release build on the Apple TV through atvloadly (Tools/install-tv.sh) and on
# the iPhone/iPad over Wi-Fi with Xcode's free Personal Team (Tools/run-device.sh). The iPhone
# install is also redone before its 7-day signature runs out; atvloadly re-signs the Apple TV app
# by itself. Needs this Mac on the home network, awake or woken for the job, with Xcode signed in.
#
# Set up once, from any checkout:  DEVICE=<udid> Tools/nightly-deploy.sh --install
#   (the iPhone/iPad's identifier is in `xcrun devicectl list devices`)
# Remove:                          Tools/nightly-deploy.sh --uninstall
# Run now instead of waiting:      launchctl kickstart gui/$UID/li.tjh.loge.nightly
# Log: ~/Library/Logs/Loge-nightly.log
set -euo pipefail

label=li.tjh.loge.nightly
agent=~/Library/LaunchAgents/$label.plist
log=~/Library/Logs/Loge-nightly.log
repo=$(git -C "${0:A:h}" rev-parse --path-format=absolute --git-common-dir)
# The job builds in a checkout of its own so it never touches work in progress.
checkout=${repo:h}/.build/nightly
# Free signatures last 7 days; reinstall with two days to spare in case a night fails.
ios_refresh_days=5

install_agent() {
    if [[ -z ${DEVICE:-} ]]; then
        echo "Set DEVICE to the iPhone/iPad's identifier from: xcrun devicectl list devices" >&2
        exit 1
    fi
    git -C "$repo" fetch --quiet origin main
    [[ -d $checkout ]] || git -C "$repo" worktree add --quiet --detach "$checkout" origin/main
    mkdir -p "${agent:h}" "${log:h}"
    # launchd runs a missed time when the Mac wakes, so a sleeping Mac catches up in the morning.
    cat >"$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array><string>/bin/zsh</string><string>-l</string><string>$checkout/Tools/nightly-deploy.sh</string></array>
    <key>EnvironmentVariables</key>
    <dict><key>DEVICE</key><string>$DEVICE</string></dict>
    <key>StartCalendarInterval</key>
    <dict><key>Hour</key><integer>2</integer><key>Minute</key><integer>30</integer></dict>
    <key>StandardOutPath</key><string>$log</string>
    <key>StandardErrorPath</key><string>$log</string>
</dict>
</plist>
EOF
    launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$UID" "$agent"
    echo "Installed $label: nightly at 02:30 for device $DEVICE; log in $log."
}

uninstall_agent() {
    launchctl bootout "gui/$UID/$label" 2>/dev/null || true
    rm -f "$agent"
    [[ -d $checkout ]] && git -C "$repo" worktree remove --force "$checkout"
    echo "Removed $label and its checkout."
}

notify() {
    osascript -e "display notification \"$1\" with title \"Loge nightly\"" || true
}

deploy() {
    echo "== $(date '+%F %T')"
    cd "$checkout"
    git fetch --quiet origin main
    local head=$(git rev-parse origin/main)
    git checkout --quiet --force --detach "$head"
    local state=.build/deployed
    mkdir -p "$state"
    local failed=()

    if [[ $(cat "$state/tvOS" 2>/dev/null) == "$head" ]]; then
        echo "Apple TV already has ${head:0:7}."
    elif Tools/install-tv.sh; then
        echo "$head" >"$state/tvOS"
    else
        failed+=("Apple TV")
    fi

    # -mtime +N matches files last written more than N days ago.
    if [[ $(cat "$state/iOS" 2>/dev/null) == "$head" && -z $(find "$state/iOS" -mtime +$ios_refresh_days) ]]; then
        echo "iPhone/iPad already has ${head:0:7}."
    elif CONFIGURATION=Release Tools/run-device.sh --no-launch; then
        echo "$head" >"$state/iOS"
        echo "Installed ${head:0:7} on the iPhone/iPad."
    else
        failed+=("iPhone/iPad")
    fi

    if (( $#failed )); then
        notify "Installing ${head:0:7} failed on ${(j: and :)failed}; see $log."
        return 1
    fi
}

main() {
    case ${1:-} in
        --install) install_agent ;;
        --uninstall) uninstall_agent ;;
        "") deploy ;;
        *) echo "Usage: Tools/nightly-deploy.sh [--install | --uninstall]" >&2; return 1 ;;
    esac
}

# zsh reads a script as it runs, and deploy moves this file to a newer version: read the call and
# the exit together so nothing after them is ever read from the new file.
main "$@"; exit
