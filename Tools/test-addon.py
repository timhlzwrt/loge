"""Local Stremio stream addon for testing loge's sources list and player.

Run with `python3 Tools/test-addon.py`, then install http://127.0.0.1:8765/manifest.json
in the app (the simulators share the Mac's network).

Serves the same sources and subtitles for every movie and episode. Binds to 127.0.0.1 only.
Logs each request's path and X-Test-Token header so header forwarding can be checked.

For local audio-language switching, first run `sh Tools/generate-playback-fixture.sh`,
then `python3 Tools/test-addon.py --port 8766 --tracks-file /tmp/loge-multiaudio.mov`.
Install its manifest in addition to the default server's manifest.
"""
import json
import argparse
from pathlib import Path
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--port", type=int, default=8765)
parser.add_argument("--bind", default="127.0.0.1", help="Interface for local or physical-device tests")
parser.add_argument("--host", default="127.0.0.1", help="Host advertised to a physical device on the LAN")
parser.add_argument("--tracks-file", type=Path, help="Local multi-audio MOV for track-switch tests")
parser.add_argument("--name", help="Name for a separate playback fixture addon and its source")
args = parser.parse_args() if __name__ == "__main__" else parser.parse_args([])
PORT = args.port
BASE = f"http://{args.host}:{PORT}"
TRACKS_FILE = args.tracks_file.resolve(strict=True) if args.tracks_file else None
TOKEN = "secret-value, with comma"
MKV = "https://test-videos.co.uk/vids/bigbuckbunny/mkv/1080/Big_Buck_Bunny_1080_10s_30MB.mkv"

MANIFEST = {
    "id": "local.mediaapp.test",
    "version": "1.0.0",
    "name": "Test Streams",
    "description": "Local test sources for loge",
    "resources": ["stream", "subtitles"],
    "types": ["movie", "series"],
    "idPrefixes": ["tt"],
    "catalogs": [],
}

STREAMS = [
    {"name": "[RD+] Test\n2160p", "description": "BluRay REMUX DV HDR10 HEVC TrueHD Atmos 7.1\n58.2 GB\nOverall: 23.6 Mbps",
     "url": MKV, "behaviorHints": {"bingeGroup": "test|2160p", "filename": "Big.Buck.Bunny.2008.2160p.REMUX.mkv", "videoSize": 29478258}},
    {"name": "[RD download] Test\n720p", "description": "WEBRip AAC2.0 x264\n310 MB", "url": MKV,
     "behaviorHints": {"videoSize": 29478258}},
    {"name": "Test\n1080p", "description": "Big Buck Bunny · BluRay H.264 DTS 5.1\n30 MB\nOverall: 23.6 Mbps", "url": MKV,
     "subtitles": [{"id": "stream-en", "url": f"{BASE}/subs/stream-en.srt", "lang": "eng"}],
     "behaviorHints": {"bingeGroup": "test|1080p", "filename": "Big_Buck_Bunny_1080_10s_30MB.mkv", "videoSize": 29478258}},
    {"name": "Test\nHEVC", "description": "Big Buck Bunny · 1080p WEB-DL HEVC DDP5.1\n1.4 GB\nOverall: 25.2 Mbps",
     "url": "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h265/1080/Big_Buck_Bunny_1080_10s_30MB.mp4",
     "behaviorHints": {"videoSize": 31462182}},
    {"name": "Test\nTracks", "description": "Apple bipbop · HLS with several audio and subtitle tracks",
     "url": "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8"},
    {"name": "Test\nHeader", "description": "Plays only if the X-Test-Token header is forwarded",
     "url": f"{BASE}/protected.mkv",
     "behaviorHints": {"proxyHeaders": {"request": {"X-Test-Token": TOKEN}}, "videoSize": 29478258}},
    {"name": "Test\nBroken", "description": "Returns 404, to check the error state",
     "url": f"{BASE}/missing.mkv"},
    {"name": "Test\nTorrent", "title": "Should be hidden", "infoHash": "0" * 40, "fileIdx": 0},
]

# What a subtitle addon such as OpenSubtitles returns; the file says where it came from.
SUBTITLES = [
    {"id": "addon-en", "url": f"{BASE}/subs/addon-en.srt", "lang": "eng"},
    {"id": "addon-de", "url": f"{BASE}/subs/addon-de.srt", "lang": "ger"},
]


def srt(name):
    return f"1\n00:00:00,500 --> 00:00:09,500\nTest subtitle: {name}\n".encode()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        token = self.headers.get("X-Test-Token")
        print(f"{self.path} token={token!r}", flush=True)
        if self.path == "/manifest.json":
            self.send_json(MANIFEST)
        elif self.path.startswith("/stream/"):
            self.send_json({"streams": STREAMS})
        elif self.path.startswith("/subtitles/"):
            self.send_json({"subtitles": SUBTITLES})
        elif self.path.startswith("/subs/") and self.path.endswith(".srt"):
            data = srt(self.path.removeprefix("/subs/").removesuffix(".srt"))
            self.send_response(200)
            self.send_header("Content-Type", "application/x-subrip")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif self.path.split("?", 1)[0] == "/tracks.mov" and TRACKS_FILE is not None:
            self.send_tracks()
        elif self.path == "/protected.mkv":
            if token == TOKEN:
                self.send_response(302)
                self.send_header("Location", MKV)
                self.end_headers()
            else:
                self.send_error(403)
        else:
            self.send_error(404)

    def send_json(self, body):
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_tracks(self):
        size = TRACKS_FILE.stat().st_size
        requested = self.headers.get("Range")
        match = re.fullmatch(r"bytes=(\d+)-(\d*)", requested or "")
        start = int(match[1]) if match else 0
        end = min(int(match[2]), size - 1) if match and match[2] else size - 1
        if (requested and not match) or start > end:
            self.send_error(416)
            return
        self.send_response(206 if requested else 200)
        self.send_header("Content-Type", "video/quicktime")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if requested:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        with TRACKS_FILE.open("rb") as video:
            video.seek(start)
            remaining = end - start + 1
            while remaining:
                data = video.read(min(remaining, 1024 * 1024))
                if not data:
                    break
                self.wfile.write(data)
                remaining -= len(data)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    if TRACKS_FILE:
        MANIFEST["name"] = args.name or "Playback Test Streams"
        STREAMS = [{"name": args.name or "Local Multi Track", "url": f"{BASE}/tracks.mov",
                    "behaviorHints": {"videoSize": TRACKS_FILE.stat().st_size}}]
    print(f"Serving on {BASE}", flush=True)
    sys.stdout.flush()
    ThreadingHTTPServer((args.bind, PORT), Handler).serve_forever()
