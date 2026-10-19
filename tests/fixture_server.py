#!/usr/bin/env python3
"""Synthetic mempool API for replay tests (DESIGN.md §11).

Serves a made-up chain from memory and writes nothing to disk, so it is safe
to run from inside the plugin directory. Point the plugin at it with:

    omarchy bar set io.github.perfect-hero.mondo-block-clock apiBase http://127.0.0.1:8787

Control endpoints (GET):
    /__admin/mine          add a block at the tip
    /__admin/mode/<mode>   ok | 429 | 500 | 404 | badjson | hang
    /__admin/state         current tip and mode

Every request is logged to stdout with a monotonic timestamp so poll spacing
can be measured independently of the plugin's own log.
"""

import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

START_HEIGHT = 900000
BLOCK_SPACING = 600
PRICE_USD = 82868

lock = threading.Lock()
state = {"tip": START_HEIGHT + 200, "tip_time": int(time.time()) - 240, "mode": "ok"}
t0 = time.monotonic()


def block(h, extras):
    with lock:
        tip, tip_time = state["tip"], state["tip_time"]
    b = {
        "id": "%064x" % h,
        "height": h,
        "timestamp": tip_time - (tip - h) * BLOCK_SPACING,
        "tx_count": 3000,
    }
    if extras:
        b["extras"] = {"pool": {"name": "Fixture Pool"}, "medianFee": 2, "reward": 312500000}
    return b


def blocks_from(h, count, extras):
    return [block(x, extras) for x in range(h, max(-1, h - count), -1)]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send(self, status, body, ctype="application/json"):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?")[0]
        with lock:
            mode, tip = state["mode"], state["tip"]
        print("%9.2f %s %s" % (time.monotonic() - t0, mode if not path.startswith("/__admin") else "admin", path), flush=True)

        if path == "/__admin/mine":
            with lock:
                state["tip"] += 1
                state["tip_time"] = int(time.time())
            return self.send(200, json.dumps({"tip": tip + 1}))
        if path.startswith("/__admin/mode/"):
            with lock:
                state["mode"] = path.rsplit("/", 1)[1]
            return self.send(200, json.dumps({"mode": state["mode"]}))
        if path == "/__admin/state":
            return self.send(200, json.dumps(state))

        if mode == "hang":
            time.sleep(30)
            return self.send(504, "timeout", "text/plain")
        if mode in ("429", "500", "404"):
            return self.send(int(mode), "fixture says %s" % mode, "text/plain")
        if mode == "badjson" and path != "/api/blocks/tip/height":
            return self.send(200, "{not json")
        if mode == "badjson":
            return self.send(200, "not-a-number", "text/plain")

        if path == "/api/blocks/tip/height":
            return self.send(200, str(tip), "text/plain")
        if path == "/api/v1/blocks":
            return self.send(200, json.dumps(blocks_from(tip, 15, True)))
        if path.startswith("/api/blocks/"):
            h = int(path.rsplit("/", 1)[1])
            return self.send(200, json.dumps(blocks_from(min(h, tip), 10, False)))
        if path == "/api/v1/difficulty-adjustment":
            done = tip % 2016
            return self.send(200, json.dumps({
                "progressPercent": done / 2016 * 100, "remainingBlocks": 2016 - done,
                "difficultyChange": 1.5, "timeAvg": BLOCK_SPACING * 1000,
            }))
        if path == "/api/v1/prices":
            return self.send(200, json.dumps({"time": int(time.time()), "USD": PRICE_USD}))
        if path == "/api/v1/mining/hashrate/3d":
            return self.send(200, json.dumps({"currentHashrate": 9.94e20, "currentDifficulty": 1.3e14}))
        return self.send(404, "not found", "text/plain")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8787)
    args = ap.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("fixture server on http://127.0.0.1:%d, tip %d" % (args.port, state["tip"]), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    main()
