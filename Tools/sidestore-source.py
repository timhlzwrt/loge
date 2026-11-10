"""Writes the SideStore/AltStore source for loge from the repository's GitHub releases.

The release workflow publishes each build of main as a release tagged `build-<number>`,
named `<version> (<number>)`, with `loge-iOS.ipa` attached. This lists the newest of them
so SideStore offers each new build as an update. The images are the project page's copies
in web/images, published next to source.json.

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

# Sizes let SideStore lay out the landscape player before the images load.
SCREENSHOTS = [
    ("iphone-player.jpg", 1800, 828),
    ("iphone-sources.jpg", 640, 687),
]

# loge's accent: white on the charcoal canvas.
TINT = "FFFFFF"

source = {
    "name": "loge",
    "identifier": "li.tjh.loge.source",
    "subtitle": "A Stremio addon client for iPhone and iPad",
    "description": (
        "Builds of loge from its GitHub repository, one for each change to the app. "
        "SideStore signs them with your own Apple ID. The Apple TV and Mac builds are on the "
        "releases page."
    ),
    "website": "https://loge.tjh.li",
    "iconURL": f"{pages_url}/icon.png",
    "headerURL": f"{pages_url}/images/tv-player.jpg",
    "tintColor": TINT,
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
        "tintColor": TINT,
        "category": "entertainment",
        "screenshots": {
            "iphone": [
                {"imageURL": f"{pages_url}/images/{name}", "width": width, "height": height}
                for name, width, height in SCREENSHOTS
            ],
        },
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
