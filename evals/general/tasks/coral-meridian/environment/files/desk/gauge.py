#!/usr/bin/env python3
"""Coral Meridian tide desk.

A raw TCP text service (one request per turn) that serves tide-gauge
readings. The client connects, sends ONE command line, and receives ONE
JSON response line per turn. Commands:

    HELLO <name>            -> open a session
    READS <station>         -> dump one station's samples (needs a session)
    EXTREME <station> <which> -> peak or trough of one station (needs a session)
    BYE                     -> close (reply then disconnect)

Reply shapes:
    {"ok":true,"kind":"hello","session":"<16hex>","desks":["..",".."]}
    {"ok":true,"kind":"reads","station":"..","samples":[[t,v],..],
     "count":N,"peak":[t,v]}
    {"ok":true,"kind":"extreme","station":"..","which":"high|low",
     "when":T,"value":V}
    {"ok":true,"kind":"bye"}
Anything malformed, unknown, or out of order gets {"ok":false,"error":..}
and the connection (and server) stay alive.

Sessions are per-connection: a READS/EXTREME before HELLO on the same
connection is rejected. Sessions are deterministic:
sha256("coral-meridian|<name>").hexdigest()[:16].

Station data lives in /app/desk/stations/*.json:
    {"station": "<name>", "samples": [[t, v], ...]}   (t:int, v:int mm)

Definitions used everywhere (client and server must agree):
  peak sample of a station  = max v; ties broken by the SMALLEST t.
  trough sample of a station= min v; ties broken by the SMALLEST t.

The listening port comes from /app/desk/desk.toml ([desk] port),
default 47231. Stdlib only; never crashes; keeps serving.
"""
import hashlib
import json
import os
import socketserver
import sys
import tomllib

DESK = "/app/desk"
DEFAULT_PORT = 47231


def load_port():
    try:
        with open(os.path.join(DESK, "desk.toml"), "rb") as fh:
            cfg = tomllib.load(fh)
        return int(cfg["desk"]["port"])
    except Exception:
        return DEFAULT_PORT


def load_stations():
    out = {}
    sdir = os.path.join(DESK, "stations")
    for fn in sorted(os.listdir(sdir)):
        if not fn.endswith(".json"):
            continue
        try:
            with open(os.path.join(sdir, fn), "r", encoding="utf-8") as fh:
                data = json.load(fh)
            out[str(data["station"])] = [[int(t), int(v)] for t, v in data["samples"]]
        except Exception:
            continue
    return out


def extreme_sample(samples, which):
    """which='high' -> max v (tie: smallest t); 'low' -> min v (tie: smallest t)."""
    best = None
    for t, v in samples:
        if best is None:
            best = (t, v)
            continue
        if which == "high":
            if v > best[1] or (v == best[1] and t < best[0]):
                best = (t, v)
        else:
            if v < best[1] or (v == best[1] and t < best[0]):
                best = (t, v)
    return best


def session_id(name):
    return hashlib.sha256(("coral-meridian|%s" % name).encode()).hexdigest()[:16]


class DeskHandler(socketserver.StreamRequestHandler):
    def reply(self, obj):
        self.wfile.write((json.dumps(obj) + "\n").encode("utf-8"))
        self.wfile.flush()

    def handle(self):
        session = None
        stations = load_stations()
        while True:
            try:
                raw = self.rfile.readline()
            except Exception:
                return
            if not raw:
                return
            line = raw.decode("utf-8", "replace").strip()
            if not line:
                self.reply({"ok": False, "error": "empty-line"})
                continue
            parts = line.split()
            cmd = parts[0].upper()
            if cmd == "HELLO" and len(parts) == 2:
                name = parts[1]
                ok = 1 <= len(name) <= 32 and all(
                    c.isalnum() or c in "_-" for c in name)
                if not ok:
                    self.reply({"ok": False, "error": "bad-name"})
                    continue
                session = session_id(name)
                self.reply({"ok": True, "kind": "hello", "session": session,
                            "desks": sorted(stations.keys())})
            elif cmd == "READS" and len(parts) == 2:
                if session is None:
                    self.reply({"ok": False, "error": "no-session"})
                    continue
                st = parts[1]
                if st not in stations:
                    self.reply({"ok": False, "error": "unknown-station",
                                "station": st})
                    continue
                samples = stations[st]
                pk = extreme_sample(samples, "high")
                self.reply({"ok": True, "kind": "reads", "station": st,
                            "samples": samples, "count": len(samples),
                            "peak": [pk[0], pk[1]]})
            elif cmd == "EXTREME" and len(parts) == 3:
                if session is None:
                    self.reply({"ok": False, "error": "no-session"})
                    continue
                st, which = parts[1], parts[2].lower()
                if st not in stations:
                    self.reply({"ok": False, "error": "unknown-station",
                                "station": st})
                    continue
                if which not in ("high", "low"):
                    self.reply({"ok": False, "error": "bad-which"})
                    continue
                t, v = extreme_sample(stations[st], which)
                self.reply({"ok": True, "kind": "extreme", "station": st,
                            "which": which, "when": t, "value": v})
            elif cmd == "BYE":
                self.reply({"ok": True, "kind": "bye"})
                return
            else:
                self.reply({"ok": False, "error": "bad-command"})


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    port = load_port()
    with Server(("127.0.0.1", port), DeskHandler) as srv:
        srv.serve_forever()
