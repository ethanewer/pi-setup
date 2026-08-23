#!/usr/bin/env python3
"""quote-svc: small HTTP service with a slow boot."""
import hashlib
import http.server
import json
import os
import random
import sys
import time

SEED = os.environ.get("SEED", "0")
PORT = int(os.environ.get("MB_PORT", "8531"))
HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    r = random.Random(f"{SEED}:t3:boot")
    delay = r.randint(45, 120)
    # build id depends on the live process id so it cannot be precomputed from source
    build = hashlib.sha256(f"{SEED}:{os.getpid()}".encode()).hexdigest()[:12]
    with open(os.path.join(HERE, "server.pid"), "w") as f:
        f.write(str(os.getpid()))
    print(f"[quote-svc] boot: loading quote corpus (pid {os.getpid()})")
    time.sleep(delay * 0.4)
    print("[quote-svc] boot: warming caches ...")
    time.sleep(delay * 0.6)

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/status":
                body = json.dumps({"status": "ready", "build": build}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, *args):
            pass

    print(f"[quote-svc] listening on http://127.0.0.1:{PORT}", flush=True)
    http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
