#!/usr/bin/env python3
"""Harbor Point structural-genomics localhost mock API (read-only fixture).

Serves a synthetic structure database stored as a JSON array of entries:

    {"accession": "7QNR", "status": "current"|"obsolete",
     "superseded_by": "8XYZ" | null,
     "chains": {"A": "<amino-acid sequence>", ...}}

Usage:  python3 /app/api_server.py <db.json> <port>

Endpoints
    GET /health                                  -> {"ok": true}
    GET /api/entries/<ACCESSION>                 -> {"accession","status",
                                                     "superseded_by","chains":[...]}
                                                    (chains is the list of chain keys)
    GET /api/sequences/<ACCESSION>/<CHAIN>       -> 200 {"accession","chain",
                                                     "lines":[...],
                                                     "sha256":"<hex>"}
                                                    for a current entry, where
                                                    "lines" is the sequence
                                                    wrapped at 80 columns and
                                                    "sha256" is the hex digest
                                                    of the joined sequence.
                                                 410 {"error":"obsolete",
                                                      "superseded_by":"<acc>"}
                                                    for an obsolete entry.
                                                 404 {"error": ...} for an
                                                    unknown accession or chain.

Accessions and chain keys are always stored uppercase in the database; the
server uppercases whatever the client sends. This fixture is only ever
contacted at 127.0.0.1; there is no outbound network in the task. The
deliverable seqfetch.py is responsible for starting this server on a free
local port and polling /health until ready.
"""
import hashlib
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse


def wrap(seq, width=80):
    if not seq:
        return [""]
    return [seq[i:i + width] for i in range(0, len(seq), width)]


def main():
    db_path = sys.argv[1]
    port = int(sys.argv[2])
    with open(db_path) as fh:
        entries = json.load(fh)
    by_acc = {e["accession"].upper(): e for e in entries}
    for e in entries:
        for key in ("accession", "status", "superseded_by", "chains"):
            if key not in e:
                sys.stderr.write("malformed entry: %r\n" % (e,))
                sys.exit(1)
        if e["status"] not in ("current", "obsolete"):
            sys.stderr.write("bad status: %r\n" % (e["status"],))
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
            path = urlparse(self.path).path
            if path == "/health":
                self._send(200, {"ok": True})
                return
            if path.startswith("/api/entries/"):
                acc = path[len("/api/entries/"):].upper().strip("/")
                ent = by_acc.get(acc)
                if ent is None:
                    self._send(404, {"error": "unknown accession"})
                    return
                self._send(200, {"accession": ent["accession"],
                                 "status": ent["status"],
                                 "superseded_by": ent["superseded_by"],
                                 "chains": sorted(ent["chains"])})
                return
            if path.startswith("/api/sequences/"):
                rest = path[len("/api/sequences/"):].strip("/").split("/")
                if len(rest) != 2:
                    self._send(404, {"error": "not found"})
                    return
                acc, chain = rest[0].upper(), rest[1].upper()
                ent = by_acc.get(acc)
                if ent is None:
                    self._send(404, {"error": "unknown accession"})
                    return
                if ent["status"] == "obsolete":
                    self._send(410, {"error": "obsolete",
                                     "superseded_by": ent["superseded_by"]})
                    return
                seq = ent["chains"].get(chain)
                if seq is None:
                    self._send(404, {"error": "unknown chain"})
                    return
                self._send(200, {"accession": ent["accession"],
                                 "chain": chain,
                                 "lines": wrap(seq, 80),
                                 "sha256": hashlib.sha256(seq.encode()).hexdigest()})
                return
            self._send(404, {"error": "not found"})

    srv = HTTPServer(("127.0.0.1", port), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()
