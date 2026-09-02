#!/usr/bin/env python3
"""Granite Grove schedule service.

Serves each person's calendar as a fresh .ics over HTTP.  Fetching requires the
correct `X-Auth` token (from the service config).  Every served calendar embeds
a per-process random session id (X-GROVE-SESSION) that exists only in a live
running process, so a calendar file written by hand or copied from disk will
never match a freshly served one.  When `--outdir` is supplied the service also
records every served .ics there (used by the verifier to diff fetch results).

Usage:
  python3 schedule_service.py --config service_config.json --port 8765 \
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
    for slot in person.get("slots", []):
        d, start, end = slot["day"], slot["start"], slot["end"]
        dnum = DOW.get(d, 0)
        daynum = int(cfg["base_date"]) + dnum
        events.append(
            "BEGIN:VEVENT\r\n"
            "DTSTAMP:20240130T000000Z\r\n"
            f"DTSTART:{daynum}T{start.replace(':', '')}00\r\n"
            f"DTEND:{daynum}T{end.replace(':', '')}00\r\n"
            f"SUMMARY:{person['display']} session\r\n"
            f"UID:g-{person['key']}-{d}@granite-grove\r\n"
            "END:VEVENT\r\n"
        )
    return (
        "BEGIN:VCALENDAR\r\n"
        "VERSION:2.0\r\n"
        "PRODID:-//Granite Grove//Scheduler v1.0//EN\r\n"
        f"X-GROVE-SESSION:{sid}\r\n"
        + "".join(events)
        + "END:VCALENDAR\r\n"
    )


class GroveHandler(http.server.BaseHTTPRequestHandler):
    server_version = "GroveScheduler/1.0"

    def log_message(self, *args):
        pass

    @property
    def cfg(self):
        return self.server.cfg

    def _auth_ok(self):
        return self.headers.get("X-Auth-Token") == self.cfg["auth_token"]

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
            self._reply(403)
            return
        if path.startswith("/person/"):
            key = path[len("/person/"):].rstrip("/")
            if key.endswith(".ics"):
                key = key[:-4]
            people = {p["key"]: p for p in self.cfg["people"]}
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


class GroveServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, addr, cfg, record_dir):
        super().__init__(addr, GroveHandler)
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
    srv = GroveServer((args.host, args.port), cfg, record)
    real_port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    print(f"GRANITE_GROVE_UP port={real_port} sid={cfg['_sid']}")
    sys.stdout.flush()
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()