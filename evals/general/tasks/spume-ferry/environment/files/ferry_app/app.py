"""spume-ferry ticketing kiosk service (stdlib only, deterministic)."""
import hashlib
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("FERRY_PORT", "8652"))

OPEN_DOCKS = [7, 21, 104]


def digest_for(dock):
    nonce = (dock * 13 + 11) % 1000000
    return hashlib.sha256(("spume:%d" % nonce).encode("utf-8")).hexdigest()


def receipt_for(dock):
    d = digest_for(dock)
    return {
        "tide": d[0:12],
        "slip": int(d[0:8], 16) % 9000 + 1000,
        "final": "pierpass-" + d[12:20],
    }


RECEIPTS = {d: receipt_for(d) for d in OPEN_DOCKS}


class Handler(BaseHTTPRequestHandler):
    server_version = "SpumeFerry/1.0"

    def log_message(self, fmt, *args):  # keep stdout quiet-ish
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/v1/announce":
            self._send(200, {"service": "spume-ferry", "api": "v1",
                             "status": "ok"})
        elif self.path == "/api/v1/routes":
            self._send(200, {"routes": [
                "GET /api/v1/announce",
                "GET /api/v1/routes",
                "GET /api/v1/receipts",
                "POST /api/v1/claim",
            ]})
        elif self.path == "/api/v1/receipts":
            self._send(200, {"open_docks": sorted(RECEIPTS.keys())})
        else:
            self._send(404, {"error": "unknown route"})

    def do_POST(self):
        if self.path != "/api/v1/claim":
            self._send(404, {"error": "unknown route"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("body must be a JSON object")
            tide = payload["tide"]
            slip = payload["slip"]
        except Exception:
            self._send(400, {"error": "malformed claim body"})
            return
        if not isinstance(tide, str) or not isinstance(slip, int):
            self._send(400, {"error": "malformed claim body"})
            return
        for dock, rec in RECEIPTS.items():
            if rec["tide"] == tide and rec["slip"] == slip:
                self._send(200, {"status": "claimed", "dock": dock,
                                 "final": rec["final"]})
                return
        self._send(409, {"error": "no receipt matches"})


def main():
    httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print("spume-ferry listening on http://127.0.0.1:%d" % PORT, flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
