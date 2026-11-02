#!/bin/sh
set -eu
repo_root=$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)
required_revision=4243d49521f1dde64353c87b6952ce6b95161aa5
if ! git -C "$repo_root" merge-base --is-ancestor "$required_revision" HEAD; then
    printf '%s\n' "Wrong base: this checkout does not include the user-confirmed todo batch." >&2
    printf '%s\n' "Read AGENTS.md and switch to the active checkout before editing, building or installing." >&2
    exit 1
fi
printf 'Checkout: %s\n' "$repo_root"
git -C "$repo_root" status --short --branch
git -C "$repo_root" log -1 --format='Base: %h %s'
