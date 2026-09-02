#!/usr/bin/env python3
"""Spreadsheet REST client for AuroraVault (deliverable /app/sheets_client.py).

Ensures the provided spreadsheet service is running at http://127.0.0.1:5002
(starting /app/src/sheets_service.py if needed), then creates (or, being
idempotent, reuses) a named spreadsheet and, nested inside it, a named
worksheet. The returned identifiers are recorded to /app/sheets_result.json:

    {"spreadsheet_id", "spreadsheet_name",
     "sheet_id", "sheet_name",
     "service_base"}

Usage:
    python3 sheets_client.py [--name <spreadsheet>] [--sheet <worksheet>]

Defaults: spreadsheet "ZephyrOps Ledger", worksheet "Ledger A". When custom edge
names are given (header/unicode/special chars) they are created/upserted the same
way. Exits 0 on success (including when the named resources already existed).
"""
import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

HOST = "127.0.0.1"
PORT = 5002
BASE = "http://%s:%d" % (HOST, PORT)
SERVICE = "/app/src/sheets_service.py"
RESULT = "/app/sheets_result.json"
DEFAULT_SPREADSHEET = "ZephyrOps Ledger"
DEFAULT_SHEET = "Ledger A"


def ensure_service():
    if _get("/health") is None:
        subprocess.Popen(
            [sys.executable, SERVICE],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
        )
        deadline = time.time() + 15
        while time.time() < deadline:
            if _get("/health") is not None:
                return
            time.sleep(0.25)
        raise RuntimeError("spreadsheet service did not start")
    return


def _request(method, url, body=None):
    req = urllib.request.Request(url, method=method)
    payload = None
    if isinstance(body, dict):
        payload = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, payload, timeout=5) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode("utf-8", "replace"))
        except Exception:
            return e.code, {}
    except Exception as e:
        return -1, {"error": str(e)}


def _get(path):
    st, obj = _request("GET", BASE + path)
    return obj if st == 200 else None


def _post(path, body):
    st, obj = _request("POST", BASE + path, body)
    return st, obj


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default=DEFAULT_SPREADSHEET)
    ap.add_argument("--sheet", default=DEFAULT_SHEET)
    args = ap.parse_args()

    try:
        ensure_service()
    except Exception as e:
        print("client error:", e, file=sys.stderr)
        return 1

    st, spr = _post("/spreadsheets", {"name": args.name})
    if st not in (200, 201):
        print("client error: create spreadsheet ->", st, spr, file=sys.stderr)
        return 1
    sid = spr["id"]
    sname = spr["name"]

    st, sht = _post("/spreadsheets/%s/sheets" % sid, {"name": args.sheet})
    if st not in (200, 201):
        print("client error: create sheet ->", st, sht, file=sys.stderr)
        return 1
    wsid = sht["id"]
    wsname = sht["name"]

    result = {
        "spreadsheet_id": sid,
        "spreadsheet_name": sname,
        "sheet_id": wsid,
        "sheet_name": wsname,
        "service_base": BASE,
    }
    with open(RESULT, "w") as fh:
        json.dump(result, fh, indent=2)
    os.chmod(RESULT, 0o644)
    print("client: spreadsheet=%s id=%s sheet=%s id=%s" % (sname, sid, wsname, wsid))
    return 0


if __name__ == "__main__":
    sys.exit(main())