"""Local Stremio stream addon for testing MediaApp's sources list and player.

Run with `python3 Tools/test-addon.py`, then install http://127.0.0.1:8765/manifest.json
in the app (the simulators share the Mac's network).

Serves the same sources for every movie and episode. Binds to 127.0.0.1 only.
Logs each request's path and X-Test-Token header so header forwarding can be checked.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 8765
BASE = f"http://127.0.0.1:{PORT}"
TOKEN = "secret-value, with comma"
MKV = "https://test-videos.co.uk/vids/bigbuckbunny/mkv/1080/Big_Buck_Bunny_1080_10s_30MB.mkv"

MANIFEST = {
    "id": "local.mediaapp.test",
    "version": "1.0.0",
    "name": "Test Streams",
    "description": "Local test sources for MediaApp",
    "resources": ["stream"],
    "types": ["movie", "series"],
    "idPrefixes": ["tt"],
    "catalogs": [],
}

STREAMS = [
    {"name": "Test\n1080p", "description": "Big Buck Bunny · MKV H.264\n30 MB", "url": MKV,
     "behaviorHints": {"bingeGroup": "test|1080p"}},
    {"name": "Test\nHEVC", "description": "Big Buck Bunny · MP4 HEVC",
     "url": "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h265/1080/Big_Buck_Bunny_1080_10s_30MB.mp4"},
    {"name": "Test\nTracks", "description": "Apple bipbop · HLS with several audio and subtitle tracks",
     "url": "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8"},
    {"name": "Test\nHeader", "description": "Plays only if the X-Test-Token header is forwarded",
     "url": f"{BASE}/protected.mkv",
     "behaviorHints": {"proxyHeaders": {"request": {"X-Test-Token": TOKEN}}}},
    {"name": "Test\nBroken", "description": "Returns 404, to check the error state",
     "url": f"{BASE}/missing.mkv"},
    {"name": "Test\nTorrent", "title": "Should be hidden", "infoHash": "0" * 40, "fileIdx": 0},
]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        token = self.headers.get("X-Test-Token")
        print(f"{self.path} token={token!r}", flush=True)
        if self.path == "/manifest.json":
            self.send_json(MANIFEST)
        elif self.path.startswith("/stream/"):
            self.send_json({"streams": STREAMS})
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

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print(f"Serving on {BASE}", flush=True)
    sys.stdout.flush()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
