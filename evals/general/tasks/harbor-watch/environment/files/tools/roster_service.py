#!/usr/bin/env python3
"""Harbor Watch duty-roster service.

Serves each crew member's watch calendar as a fresh .ics over HTTP.  Requests
for /roster/*.ics require the correct ``Authorization: Bearer <token>`` header
(token lives in the service config).  Every served calendar embeds a
per-process random session id (X-HARBOR-RUN) that exists only in a live running
process, so a calendar written by hand or copied from disk can never match a
freshly served one.  When ``--outdir`` is supplied the service also records
every served .ics there (used by the verifier to diff fetch results).

Usage:
  python3 roster_service.py --config service_config.json --port 0 \
      [--outdir /tmp/served]
"""
import argparse
import http.server
import json
import os
import secrets
import sys
import threading
import time

DOW = {"Mon": 0, "Tue": 1, "Wed": 2, "Thu": 3, "Fri": 4, "Sat": 5, "Sun": 6}


def build_ics(cfg, person, sid):
    events = []
    base = int(cfg["base_date"])
    for w in person.get("watches", []):
        dnum = DOW.get(w["day"], 0)
        day = base + dnum
        events.append(
            "BEGIN:VEVENT\r\n"
            "DTSTAMP:20320502T000000Z\r\n"
            f"DTSTART:{day}T{w['start'].replace(':', '')}00\r\n"
            f"DTEND:{day}T{w['end'].replace(':', '')}00\r\n"
            f"SUMMARY:{person['display']} watch\r\n"
            f"UID:hw-{person['key']}-{w['day']}-{w['start']}@harbor-watch\r\n"
            f"DESCRIPTION:{cfg['terminal']} duty desk\r\n"
            "END:VEVENT\r\n"
        )
    return (
        "BEGIN:VCALENDAR\r\n"
        "VERSION:2.0\r\n"
        "PRODID:-//Harbor Watch//Roster v2.4//EN\r\n"
        f"X-HARBOR-RUN:{sid}\r\n"
        f"X-TERMINAL:{cfg['terminal']}\r\n"
        + "".join(events)
        + "END:VCALENDAR\r\n"
    )


class WatchHandler(http.server.BaseHTTPRequestHandler):
    server_version = "HarborWatchRoster/2.4"

    def log_message(self, *args):
        pass

    @property
    def cfg(self):
        return self.server.cfg

    def _auth_ok(self):
        auth = self.headers.get("Authorization", "")
        return auth == "Bearer " + self.cfg["auth_token"]

    def _reply(self, code, body=b""):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        path = self.path
        if path == "/health":
            self._reply(200, b"ok")
            return
        if not self._auth_ok():
            self._reply(401)
            return
        if path.startswith("/roster/"):
            key = path[len("/roster/"):].rstrip("/")
            if key.endswith(".ics"):
                key = key[:-4]
            people = {p["key"]: p for p in self.cfg["crew"]}
            if key not in people:
                self._reply(404)
                return
            body = build_ics(self.cfg, people[key], self.cfg["_sid"])
            self._reply(200, body.encode("utf-8"))
            record = self.cfg.get("record_dir")
            if record:
                os.makedirs(record, exist_ok=True)
                with open(os.path.join(record, key + ".ics"), "w") as fh:
                    fh.write(body)
            return
        self._reply(404)


class WatchServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, addr, cfg, record_dir):
        super().__init__(addr, WatchHandler)
        self.cfg = cfg
        self.cfg["record_dir"] = record_dir


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--outdir", default=None)
    args = ap.parse_args()

    with open(args.config) as fh:
        cfg = json.load(fh)
    if "_sid" not in cfg:
        cfg["_sid"] = secrets.token_hex(8)

    record = os.path.abspath(args.outdir) if args.outdir else None
    srv = WatchServer((args.host, args.port), cfg, record)
    real_port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    print(f"HARBOR_WATCH_UP port={real_port} sid={cfg['_sid']}")
    sys.stdout.flush()
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
