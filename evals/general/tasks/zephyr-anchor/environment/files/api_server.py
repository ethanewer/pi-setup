#!/usr/bin/env python3
"""Zephyr localhost mock API server (read-only fixture, NOT a deliverable).

Serves two endpoints for a synthetic fluorescent-protein database stored as a
JSON array of records, each of the form:

    {"id": "...", "sequence": "<amino acid string>",
     "excitation_nm": <int>, "emission_nm": <int>}

Usage:  python3 /app/data_server.py <api.json> <port>

Endpoints
    GET /health                          -> {"ok": true}
    GET /api/spectra?id=<id>             -> {"id","excitation_nm","emission_nm"}
    GET /api/sequences?id=<id>           -> {"id","sequence"}
Both data endpoints return HTTP 404 {"error": ...} for an unknown id.

This fixture is only ever contacted at 127.0.0.1; there is no outbound
network in the task. The deliverable api_client.py is responsible for starting
this server on a free local port and polling /health until it is ready.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse


def main():
    db_path = sys.argv[1]
    port = int(sys.argv[2])
    with open(db_path) as fh:
        records = json.load(fh)
    by_id = {rec["id"]: rec for rec in records}
    for rec in records:
        for key in ("id", "sequence", "excitation_nm", "emission_nm"):
            if key not in rec:
                sys.stderr.write("malformed record: %r\n" % (rec,))
                sys.exit(1)

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
            rec = by_id.get(pid) if pid else None
            if path == "/api/spectra" and pid:
                if rec is None:
                    self._send(404, {"error": "unknown protein id"})
                    return
                self._send(200, {"id": rec["id"],
                                 "excitation_nm": rec["excitation_nm"],
                                 "emission_nm": rec["emission_nm"]})
                return
            if path == "/api/sequences" and pid:
                if rec is None:
                    self._send(404, {"error": "unknown sequence id"})
                    return
                self._send(200, {"id": rec["id"], "sequence": rec["sequence"]})
                return
            self._send(404, {"error": "not found"})

    srv = HTTPServer(("127.0.0.1", port), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()