#!/usr/bin/env python3
"""Glacier Ridge microscope-core localhost mock spectra API (read-only fixture).

Serves a synthetic fluorescent-protein spectral database stored as a JSON
array of records, each of the form:

    {"id": "...", "sequence": "<amino acids>", "excitation_nm": <int>,
     "emission_nm": <int>, "brightness": <number>, "status": "active"|"withdrawn"}

Usage:  python3 /app/api_server.py <proteins.json> <port>

Endpoints
    GET /health                              -> {"ok": true}
    GET /api/spectra?id=<id>                 -> {"id","excitation_nm","emission_nm","brightness"}
    GET /api/status?id=<id>                  -> {"id","status"}
    GET /api/spectra?page=<N>&per_page=<M>   -> paginated spectra listing:
                                                {"page","per_page","total","items":[...]}
                                                where each item is
                                                {"id","excitation_nm","emission_nm","brightness"}.
                                                per_page is capped at 5 by the server.

Both /api/spectra?id= and /api/status?id= return HTTP 404 {"error": ...} for an
unknown id. This fixture is only ever contacted at 127.0.0.1; there is no
outbound network in the task. The deliverable spectra_client.py is responsible
for starting this server on a free local port and polling /health until ready.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

MAX_PER_PAGE = 5


def main():
    db_path = sys.argv[1]
    port = int(sys.argv[2])
    with open(db_path) as fh:
        records = json.load(fh)
    by_id = {rec["id"]: rec for rec in records}
    for rec in records:
        for key in ("id", "sequence", "excitation_nm", "emission_nm",
                    "brightness", "status"):
            if key not in rec:
                sys.stderr.write("malformed record: %r\n" % (rec,))
                sys.exit(1)

    def spectra_item(rec):
        return {"id": rec["id"],
                "excitation_nm": rec["excitation_nm"],
                "emission_nm": rec["emission_nm"],
                "brightness": rec["brightness"]}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):  # keep logs quiet
            pass

        def _send(self, code, payload):
            body = json.dumps(payload).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            parsed = urlparse(self.path)
            path = parsed.path
            q = parse_qs(parsed.query)
            if path == "/health":
                self._send(200, {"ok": True})
                return
            pid = (q.get("id") or [None])[0]
            if path == "/api/spectra":
                # paginated listing mode
                if pid is None:
                    try:
                        page = max(1, int((q.get("page") or ["1"])[0]))
                    except ValueError:
                        page = 1
                    try:
                        per_page = int((q.get("per_page") or ["5"])[0])
                    except ValueError:
                        per_page = 5
                    per_page = max(1, min(per_page, MAX_PER_PAGE))
                    total = len(records)
                    start = (page - 1) * per_page
                    items = [spectra_item(r) for r in records[start:start + per_page]]
                    self._send(200, {"page": page, "per_page": per_page,
                                     "total": total, "items": items})
                    return
                rec = by_id.get(pid)
                if rec is None:
                    self._send(404, {"error": "unknown protein id"})
                    return
                self._send(200, spectra_item(rec))
                return
            if path == "/api/status":
                rec = by_id.get(pid) if pid else None
                if rec is None:
                    self._send(404, {"error": "unknown protein id"})
                    return
                self._send(200, {"id": rec["id"], "status": rec["status"]})
                return
            self._send(404, {"error": "not found"})

    srv = HTTPServer(("127.0.0.1", port), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()
