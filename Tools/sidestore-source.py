"""Writes the SideStore/AltStore source for loge from the repository's GitHub releases.

The release workflow publishes each build of main as a release tagged `build-<number>`,
named `<version> (<number>)`, with `loge-iOS.ipa` attached. This lists the newest of them
so SideStore offers each new build as an update.

    gh api repos/<owner>/<repo>/releases --paginate > releases.json
    python3 Tools/sidestore-source.py releases.json <pages URL> > source.json
"""
import json
import re
import sys

KEPT_VERSIONS = 10

releases_path, pages_url = sys.argv[1], sys.argv[2].rstrip("/")
with open(releases_path) as file:
    releases = json.load(file)

versions = []
for release in releases:
    name = re.fullmatch(r"(\S+) \((\d+)\)", release.get("name") or "")
    ipa = next((a for a in release.get("assets", []) if a["name"] == "loge-iOS.ipa"), None)
    if release.get("draft") or not release["tag_name"].startswith("build-") or not name or not ipa:
        continue
    versions.append({
        "version": name[1],
        "buildVersion": name[2],
        "date": release["published_at"],
        "localizedDescription": (release.get("body") or "").strip(),
        "downloadURL": ipa["browser_download_url"],
        "size": ipa["size"],
        "minOSVersion": "26.0",
    })
versions.sort(key=lambda v: int(v["buildVersion"]), reverse=True)

source = {
    "name": "loge",
    "identifier": "li.tjh.loge.source",
    "subtitle": "A Stremio addon client for iPhone and iPad",
    "website": "https://github.com/timhlzwrt/loge",
    "iconURL": f"{pages_url}/icon.png",
    "apps": [{
        "name": "loge",
        "bundleIdentifier": "li.tjh.MediaApp",
        "developerName": "Tim Holzwarth",
        "subtitle": "Stremio addons, played with mpv",
        "localizedDescription": (
            "Browse catalogs from your Stremio addons, read details and play streams with mpv. "
            "Movies, series, search and IMDb ratings are built in; add your own playback addon to watch. "
            "loge has no content of its own."
        ),
        "iconURL": f"{pages_url}/icon.png",
        "tintColor": "1C1C1E",
        "category": "entertainment",
        "versions": versions[:KEPT_VERSIONS],
        "appPermissions": {
            "entitlements": [],
            "privacy": {},
        },
    }],
    "news": [],
}
json.dump(source, sys.stdout, indent=2)
sys.stdout.write("\n")
