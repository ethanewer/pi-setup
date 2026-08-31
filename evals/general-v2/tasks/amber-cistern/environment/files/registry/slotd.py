#!/usr/bin/env python3
"""slotd - depot slot registry service (amber-cistern fixture).

Usage: python3 slotd.py <table.json> <port>

A raw TCP text service. STRICT single-request-per-turn discipline: the server
accepts a connection, reads exactly ONE request line, writes exactly ONE JSON
response line, and closes the connection. Any additional bytes written before
the response is read are lost; a client that pipelines two requests on one
connection only ever sees one answer.

Requests (one line, UTF-8, terminated by \n):
  PING                    -> {"ok":true,"kind":"pong","slots":<int>}
  SLOT <zone>/<row>/<bay> -> {"ok":true,"kind":"slot",...,"token":"<16hex>"}
                             (key present in the table)
                             {"ok":false,"kind":"error","error":"unknown-slot"}
                             (well-formed key not in the table)
  anything else           -> {"ok":false,"kind":"error","error":"bad-request"}

The token of a slot is deterministic: sha256("slotd-v1:" + key) truncated to
16 hex chars. It depends only on the slot key, never on time or state.
"""
import hashlib
import json
import re
import socket
import sys

KEY_RE = re.compile(r"^[A-Z]{1,8}/[0-9]+/[0-9]+$")


def token_for(key):
    return hashlib.sha256(("slotd-v1:" + key).encode("utf-8")).hexdigest()[:16]


def respond(req, table):
    if req == "PING":
        return {"ok": True, "kind": "pong", "slots": len(table)}
    parts = req.split(None, 1)
    if len(parts) != 2 or parts[0] != "SLOT":
        return {"ok": False, "kind": "error", "error": "bad-request"}
    key = parts[1].strip()
    if not KEY_RE.match(key):
        return {"ok": False, "kind": "error", "error": "bad-request"}
    rec = table.get(key)
    if rec is None:
        return {"ok": False, "kind": "error", "error": "unknown-slot"}
    zone, row, bay = key.split("/")
    return {
        "ok": True,
        "kind": "slot",
        "slot": key,
        "zone": zone,
        "row": int(row),
        "bay": int(bay),
        "sku": str(rec["sku"]),
        "qty": int(rec["qty"]),
        "token": token_for(key),
    }


def handle(conn, table):
    try:
        conn.settimeout(10)
        with conn:
            f = conn.makefile("rwb")
            raw = f.readline(65536)
            try:
                req = raw.decode("utf-8", "replace").rstrip("\r\n")
            except Exception:
                req = ""
            resp = respond(req, table)
            f.write((json.dumps(resp) + "\n").encode("utf-8"))
            f.flush()
    except Exception:
        pass


def main():
    table_path, port = sys.argv[1], int(sys.argv[2])
    with open(table_path, "r", encoding="utf-8") as fh:
        table = json.load(fh)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(64)
    print("slotd listening on 127.0.0.1:%d with %d slots" % (port, len(table)),
          flush=True)
    while True:
        conn, _ = srv.accept()
        handle(conn, table)


if __name__ == "__main__":
    main()
