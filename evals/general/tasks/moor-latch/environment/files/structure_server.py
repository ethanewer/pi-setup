#!/usr/bin/env python3
"""Moorfield localhost structure-database API (read-only fixture, NOT a
deliverable).

Serves a synthetic structural-genomics archive stored as a JSON array of
entries, each of the form:

    {"entry_id": "...", "title": "...",
     "chains": [{"chain_id": "...", "sequence": "<amino acids>"}, ...]}

Usage:  python3 /app/structure_server.py <entries.json> <port>

Endpoints
    GET /health                            -> {"ok": true}
    GET /api/entry/<entry_id>              -> {"entry_id","title","chains":
                                              [{"chain_id","length"}, ...]}
                                              (metadata only: NO sequences)
    GET /api/sequence/<entry_id>/<chain_id>-> {"entry_id","chain_id","sequence"}
    anything else                          -> 404 {"error": ...}

Unknown entry ids or chain ids return HTTP 404 {"error": ...}.

This fixture is only ever contacted at 127.0.0.1; there is no outbound network
in the task. The deliverable struct_client.py is responsible for starting this
server on a free local port and polling /health until it is ready.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


def main():
    db_path = sys.argv[1]
    port = int(sys.argv[2])
    with open(db_path) as fh:
        entries = json.load(fh)
    by_id = {}
    for entry in entries:
        for key in ("entry_id", "title", "chains"):
            if key not in entry:
                sys.stderr.write("malformed entry: %r\n" % (entry,))
                sys.exit(1)
        by_id[entry["entry_id"]] = entry

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
            path = self.path
            if path == "/health":
                self._send(200, {"ok": True})
                return
            if path.startswith("/api/entry/"):
                eid = path[len("/api/entry/"):]
                entry = by_id.get(eid)
                if entry is None:
                    self._send(404, {"error": "unknown entry id"})
                    return
                self._send(200, {
                    "entry_id": entry["entry_id"],
                    "title": entry["title"],
                    "chains": [{"chain_id": ch["chain_id"],
                                "length": len(ch["sequence"])}
                               for ch in entry["chains"]],
                })
                return
            if path.startswith("/api/sequence/"):
                rest = path[len("/api/sequence/"):]
                eid, _, cid = rest.partition("/")
                entry = by_id.get(eid)
                chain = None
                if entry is not None:
                    for ch in entry["chains"]:
                        if ch["chain_id"] == cid:
                            chain = ch
                            break
                if entry is None or chain is None:
                    self._send(404, {"error": "unknown entry or chain id"})
                    return
                self._send(200, {"entry_id": entry["entry_id"],
                                 "chain_id": chain["chain_id"],
                                 "sequence": chain["sequence"]})
                return
            self._send(404, {"error": "not found"})

    srv = HTTPServer(("127.0.0.1", port), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()
