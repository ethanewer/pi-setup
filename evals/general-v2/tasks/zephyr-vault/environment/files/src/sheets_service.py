#!/usr/bin/env python3
"""AuroraVault spreadsheet REST mock (provided infrastructure).

A tiny HTTP service that persists named spreadsheets and, nested inside each,
named worksheets. State is written to /app/data/sheets_store.json so resources
survive across process restarts (oracle run, agent, verifier).

Behaviour contract (this is what /app/sheets_client.py and hidden cases rely on):

  GET  /health                         -> {"ok": true}
  GET  /spreadsheets                   -> {"spreadsheets": [{"id","name"}]}
  POST /spreadsheets   {"name": ...}   ->
         * empty/missing/non-string name -> 400 {"error": ...}
         * name already present -> 200 + the EXISTING spreadsheet (upsert, idempotent)
         * otherwise -> 201 {"id","name","sheets":[]}
  GET  /spreadsheets/<sid>             -> 404 if absent, else {"id","name","sheets":[{"id","name"}]}
  POST /spreadsheets/<sid>/sheets
                         {"name":...}  -> 400 invalid name; 404 unknown sid; else
                                         200 existing (same sheet name) or 201 new
                                         {"id","name","spreadsheet_id"}
  GET  /spreadsheets/<sid>/sheets/<wsid> -> 404 if absent, else {"id","name","spreadsheet_id"}
"""
import json
import os
import socket
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = int(os.environ.get("AURORA_SHEETS_PORT", "5002"))
STORE = os.environ.get("AURORA_SHEETS_STORE", "/app/data/sheets_store.json")

_lock = threading.Lock()


def _store():
    if os.path.exists(STORE):
        try:
            with open(STORE) as fh:
                return json.load(fh)
        except Exception:
            return {"spreadsheets": []}
    return {"spreadsheets": []}


def _save(state):
    os.makedirs(os.path.dirname(STORE), exist_ok=True)
    with open(STORE, "w") as fh:
        json.dump(state, fh)


def _sheet_summary(sh):
    return {"id": sh["id"], "name": sh["name"]}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # keep logs quiet
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode())
        except Exception:
            return {"__bad_json__": True}

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/health":
            return self._send(200, {"ok": True})
        if path == "/spreadsheets":
            st = _store()
            return self._send(200, {"spreadsheets": [{"id": s["id"], "name": s["name"]} for s in st["spreadsheets"]]})
        parts = [p for p in path.split("/") if p]
        if len(parts) == 2 and parts[0] == "spreadsheets":
            st = _store()
            for s in st["spreadsheets"]:
                if s["id"] == parts[1]:
                    return self._send(200, {"id": s["id"], "name": s["name"],
                                            "sheets": [_sheet_summary(x) for x in s["sheets"]]})
            return self._send(404, {"error": "spreadsheet not found"})
        if len(parts) == 4 and parts[0] == "spreadsheets" and parts[2] == "sheets":
            st = _store()
            for s in st["spreadsheets"]:
                if s["id"] == parts[1]:
                    for sh in s["sheets"]:
                        if sh["id"] == parts[3]:
                            return self._send(200, {"id": sh["id"], "name": sh["name"],
                                                    "spreadsheet_id": parts[1]})
                    return self._send(404, {"error": "sheet not found"})
            return self._send(404, {"error": "spreadsheet not found"})
        return self._send(404, {"error": "no such route"})

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        data = self._read_json()
        if data.get("raw_bad_json"):
            return self._send(400, {"error": "malformed json"})
        if path == "/spreadsheets":
            name = data.get("name")
            if not isinstance(name, str) or not name.strip():
                return self._send(400, {"error": "spreadsheet name required"})
            name = name.strip()
            with _lock:
                st = _store()
                for s in st["spreadsheets"]:
                    if s["name"] == name:
                        return self._send(200, {"id": s["id"], "name": s["name"], "sheets": [_sheet_summary(x) for x in s["sheets"]]})
                row = {"id": "ss-" + uuid.uuid4().hex[:8], "name": name, "sheets": []}
                st["spreadsheets"].append(row)
                _save(st)
            return self._send(201, {"id": row["id"], "name": row["name"], "sheets": []})
        parts = [p for p in path.split("/") if p]
        if len(parts) == 3 and parts[0] == "spreadsheets" and parts[2] == "sheets":
            sid = parts[1]
            name = data.get("name")
            if not isinstance(name, str) or not name.strip():
                return self._send(400, {"error": "sheet name required"})
            name = name.strip()
            with _lock:
                st = _store()
                for s in st["spreadsheets"]:
                    if s["id"] == sid:
                        for sh in s["sheets"]:
                            if sh["name"] == name:
                                return self._send(200, {"id": sh["id"], "name": sh["name"], "spreadsheet_id": sid})
                        row = {"id": "ws-" + uuid.uuid4().hex[:8], "name": name}
                        s["sheets"].append(row)
                        _save(st)
                        return self._send(201, {"id": row["id"], "name": row["name"], "spreadsheet_id": sid})
                return self._send(404, {"error": "spreadsheet not found"})
        return self._send(404, {"error": "no such route"})


def main():
    with _lock:
        _store()  # ensure store dir/file seeded
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    srv.serve_forever()


if __name__ == "__main__":
    main()