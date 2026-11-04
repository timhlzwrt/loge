#!/bin/bash
# Resume a draft after transient GitHub failures; published assets stay immutable.
set -euo pipefail
if (( $# < 5 )); then
    echo "Usage: $0 TAG TITLE COMMIT NOTES_FILE ASSET..." >&2
    exit 1
fi
tag=$1 title=$2 commit=$3 notes=$4
shift 4
[[ -f "$notes" ]] || { echo "Release notes not found: $notes" >&2; exit 1; }
for asset in "$@"; do
    [[ -s "$asset" ]] || { echo "Release asset missing or empty: $asset" >&2; exit 1; }
done
expected=$(printf '%s\n' "${@##*/}" | jq -Rsc 'split("\n")[:-1]')
observe() {
    state=$(gh release view "$tag" --json isDraft,assets) &&
        jq -e '(.isDraft | type) == "boolean" and (.assets | type) == "array"' <<< "$state" >/dev/null
}
complete() {
    jq -e --argjson expected "$expected" '
        [.assets[] | select(.size > 0) | .name] as $uploaded |
        ($expected - $uploaded | length) == 0' <<< "$state" >/dev/null
}
published() { jq -e '.isDraft == false' <<< "$state" >/dev/null; }
accept_published() {
    if complete; then
        echo "Release $tag is published with all expected assets."
        exit 0
    fi
    echo "Published release $tag has missing or empty assets; refusing to change it." >&2
    exit 1
}
for attempt in 1 2 3; do
    if ! observe; then
        # Creation may succeed even when its HTTP response is lost.
        gh release create "$tag" --draft --target "$commit" --title "$title" --notes-file "$notes" || true
        if ! observe; then
            echo "Could not reconcile release $tag (attempt $attempt/3)." >&2
            if (( attempt < 3 )); then sleep 2; fi
            continue
        fi
    fi
    if published; then accept_published; fi
    if gh release upload "$tag" "$@" --clobber && observe; then
        if published; then accept_published; fi
        if complete; then
            gh release edit "$tag" --draft=false --latest || true
            if observe && published; then accept_published; fi
        else
            echo "Draft release $tag still has missing or empty assets." >&2
        fi
    fi
    echo "Release $tag is not published yet (attempt $attempt/3)." >&2
    if (( attempt < 3 )); then sleep 2; fi
done
if observe && published; then accept_published; fi
echo "Could not publish release $tag after 3 attempts; rerun to resume any draft." >&2
exit 1
