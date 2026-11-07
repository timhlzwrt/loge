#!/bin/bash
# Sign the installer and its feed with the same Sparkle version embedded in the app.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 2 || ! "$1" =~ ^build-[0-9]+$ || ! -f "$2" ]]; then
    echo "Usage: $0 build-N NOTES_FILE" >&2
    exit 1
fi
tag=$1 notes=$2
tools=.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin
out=.build/mac-update
[[ -x "$tools/generate_appcast" ]] || { echo "Build the Mac app first to download Sparkle's signing tools." >&2; exit 1; }
[[ -n "${SPARKLE_PRIVATE_KEY:-}" ]] || { echo "Set SPARKLE_PRIVATE_KEY to loge's update signing key." >&2; exit 1; }
mkdir -p "$out"
cp .build/dmg/loge-macOS.dmg "$out/loge-macOS.dmg"
cp "$notes" "$out/loge-macOS.md"
# A rerun must sign the current archive, never reuse a cached entry for the same build.
rm -f "$out/appcast.xml"
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$tools/generate_appcast" \
    --ed-key-file - --maximum-deltas 0 --embed-release-notes \
    --download-url-prefix "https://github.com/timhlzwrt/loge/releases/download/$tag/" \
    "$out"
# generate_appcast can warn about a mismatched key without failing. Never publish
# a feed that has no signed archive, or points at a different build's asset.
python3 - "$out" "$tag" <<'PY'
import base64
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

out, tag = Path(sys.argv[1]), sys.argv[2]
namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(out / 'appcast.xml').findall('./channel/item')
if len(items) != 1:
    sys.exit('Expected exactly one Mac update in the generated feed.')
item = items[0]
enclosure = item.find('enclosure')
if enclosure is None or len(base64.b64decode(enclosure.get(namespace + 'edSignature', ''), validate=True)) != 64:
    sys.exit('The Mac archive is unsigned. Check SPARKLE_PRIVATE_KEY matches SUPublicEDKey.')
if item.findtext(namespace + 'version') != tag.removeprefix('build-'):
    sys.exit('The Mac app build number does not match the release tag.')
expected_url = f'https://github.com/timhlzwrt/loge/releases/download/{tag}/loge-macOS.dmg'
if enclosure.get('url') != expected_url or enclosure.get('length') != str((out / 'loge-macOS.dmg').stat().st_size):
    sys.exit('The Mac feed does not match the release archive.')
PY
printf '%s' "$SPARKLE_PRIVATE_KEY" | "$tools/sign_update" --ed-key-file - --verify "$out/appcast.xml"
