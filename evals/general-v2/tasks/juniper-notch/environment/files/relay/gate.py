#!/usr/bin/env python3
"""Juniper Notch survey gate.

A raw TCP text server (one request per turn). The client connects, sends a
single command line, receives a single JSON response line, and (for a survey)
may send one follow-up. Commands:

    MAP                         -> describe the active site map
    SURVE <siteName>            -> survey one site from the map (token)
    QUIT                        -> close the connection

MAP replies:
    {"ok":true,"kind":"map","target":{"row":R,"col":C},
     "sites":[{"name":"...","row":R,"col":C}, ...]}

SURVE replies (site must be present in the active map):
    {"ok":true,"kind":"site","site":"<name>","row":R,"col":C,"token":"<40hex>"}

The token is deterministic for a site: sha256("<site>|<row>|<col>|<salt>")[0:40].
Unknown/malformed commands get {"ok":false,...}. Never crash; keep serving.

This gate is unauthenticated and is part of the relay fixture. Do not modify it.
"""
import hashlib
import json
import os
import socket
import sys
import tomllib

APP = "/app"
RELAY = os.path.join(APP, "relay")

SALT = "JuniperNotchRelaySalt77"

PORT = 43979
DEFAULT_MAP = os.path.join(RELAY, "maps", "default.json")


def load_station():
    try:
        with open(os.path.join(RELAY, "station.toml"), "rb") as fh:
            cfg = tomllib.load(fh)
        return int(cfg["gate"]["port"])
    except Exception:
        return PORT


def load_map(path):
    with open(path) as fh:
        return json.load(fh)


def site_token(name, row, col):
    raw = "%s|%d|%d|%s" % (name, row, col, SALT)
    return hashlib.sha256(raw.encode()).hexdigest()[:40]


def handle_map(mp):
    return {"ok": True, "kind": "map", "target": mp["target"],
            "sites": mp["sites"]}


def handle_site(mp, site_id):
    for s in mp["sites"]:
        if s["name"] == site_id:
            return {"ok": True, "kind": "site", "site": s["name"],
                    "row": int(s["row"]), "col": int(s["col"]),
                    "token": site_token(s["name"], int(s["row"]), int(s["col"]))}
    return {"ok": False, "error": "unknown site"}


def serve(port, mappath):
    mp = load_map(mappath)
    lsock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    lsock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    lsock.bind(("127.0.0.1", port))
    lsock.listen(16)
    print("GATE-UP %d" % port, flush=True)
    while True:
        conn, _ = lsock.accept()
        conn.settimeout(30.0)
        try:
            with conn:
                f = conn.makefile("r", encoding="utf-8")
                while True:
                    line = f.readline()
                    if not line:
                        break
                    parts = line.strip().split()
                    if not parts:
                        continue
                    cmd = parts[0].upper()
                    if cmd == "MAP":
                        reply = handle_map(mp)
                    elif cmd == "SURVE" and len(parts) >= 2:
                        reply = handle_site(mp, parts[1])
                    else:
                        reply = {"ok": False, "error": "malformed request"}
                    conn.sendall((json.dumps(reply) + "\n").encode("utf-8"))
        except Exception:
            pass


if __name__ == "__main__":
    port = load_station()
    mappath = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MAP
    if not os.path.exists(mappath):
        mappath = DEFAULT_MAP
    serve(port, mappath)