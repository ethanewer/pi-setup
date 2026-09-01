#!/usr/bin/env python3
"""badgedesk — a small, self-contained attendee-registry service used by the
velvet-atlas scenario. Serves a REST-style API over HTTP and persists state as
JSON under a store directory. An append-only audit.ndjson records every
state-changing operation so the work can be confirmed to have gone through
the API.

Run it with:
    python3 badgedesk.py --store /app/store --port 8841

Store layout:
  attendees.json  {"attendees": [{"attendee_id", "full_name", "email",
                                  "affiliation", "badge_code"}]}
  audit.ndjson    one JSON object per state-changing API call

Endpoints:
  GET    /health
  GET    /api/v1/attendees
  GET    /api/v1/attendees/{id}
  GET    /api/v1/attendees/{id}/badge
  DELETE /api/v1/attendees/{id}
"""
import argparse
import json
import os
import secrets
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, unquote


class Store:
    def __init__(self, root):
        self.root = root
        os.makedirs(root, exist_ok=True)

    def _path(self, name):
        return os.path.join(self.root, name)

    def read(self, name, default):
        p = self._path(name)
        if not os.path.exists(p):
            return default
        with open(p) as fh:
            return json.load(fh)

    def write(self, name, data):
        with open(self._path(name), "w") as fh:
            json.dump(data, fh, indent=2)

    def audit(self, entry):
        with open(self._path("audit.ndjson"), "a") as fh:
            fh.write(json.dumps(entry) + "\n")


class Handler(BaseHTTPRequestHandler):
    store = None

    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        data = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = unquote(parsed.path.rstrip("/"))
        if path == "/health":
            return self._send(200, {"service": "badgedesk", "version": "1.2"})
        if path.startswith("/api/v1/attendees"):
            rest = path[len("/api/v1/attendees"):].lstrip("/")
            attendees = self.store.read(
                "attendees.json", {"attendees": []}).get("attendees", [])
            if rest == "":
                return self._send(200, {"attendees": attendees})
            parts = rest.split("/")
            row = next((a for a in attendees
                        if a.get("attendee_id") == parts[0]), None)
            if row is None:
                return self._send(404, {"error": "no_such_attendee"})
            if len(parts) == 1:
                return self._send(200, row)
            if len(parts) == 2 and parts[1] == "badge":
                return self._send(200, {"attendee_id": row["attendee_id"],
                                        "badge_code": row.get("badge_code")})
        return self._send(404, {"error": "not_found"})

    def do_DELETE(self):
        parsed = urlparse(self.path)
        path = unquote(parsed.path.rstrip("/"))
        if path.startswith("/api/v1/attendees"):
            rest = path[len("/api/v1/attendees"):].lstrip("/")
            parts = rest.split("/")
            if len(parts) != 1 or not parts[0]:
                return self._send(404, {"error": "not_found"})
            doc = self.store.read("attendees.json", {"attendees": []})
            attendees = doc.get("attendees", [])
            keep = [a for a in attendees
                    if a.get("attendee_id") != parts[0]]
            if len(keep) == len(attendees):
                return self._send(404, {"error": "no_such_attendee"})
            doc["attendees"] = keep
            self.store.write("attendees.json", doc)
            self.store.audit({"op": "attendee.delete",
                              "attendee_id": parts[0]})
            return self._send(200, {"deleted": parts[0]})
        return self._send(404, {"error": "not_found"})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--store", default="/app/store")
    ap.add_argument("--port", type=int, default=8841)
    args = ap.parse_args()

    store = Store(args.store)
    if not os.path.exists(os.path.join(store.root, "attendees.json")):
        store.write("attendees.json", {"attendees": []})

    Handler.store = store
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("badgedesk ready on port %d" % args.port, flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
