#!/usr/bin/env bash
# Oracle for dune-fathom. Builds the deliverable /app/server.py, seeds the
# SQLite accounts DB from the source CSV, exports /app/dump.csv, runs the local
# fixture server and fetches both remote files byte-for-byte into /app/delivered,
# then boots the API server to produce /app/server.out.
set -euo pipefail
cd /app

# ---- 1. Author the API server -------------------------------------------------
cat > /app/server.py << 'PY'
import csv
import json
import os
import sqlite3

from flask import Flask, Response, jsonify, request

PORT = 8787
DB = "/app/data/dump_chain.db"
SRC = "/app/data/accounts.csv"

CONF_BLOCK = {1000, 2000, 3000, 4000}
PEND_BLOCK = {1500, 2500}
CONF_TX = {7001, 7002, 8001}
PEND_TX = {9000, 9100}

app = Flask(__name__)


def fib(n: int) -> int:
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a


def seed():
    os.makedirs("/app/data", exist_ok=True)
    con = sqlite3.connect(DB)
    try:
        cur = con.cursor()
        cur.execute(
            "CREATE TABLE IF NOT EXISTS accounts ("
            "id INTEGER PRIMARY KEY, address TEXT, balance INTEGER)"
        )
        if cur.execute("SELECT COUNT(*) FROM accounts").fetchone()[0] == 0:
            with open(SRC, newline="") as fh:
                for row in csv.DictReader(fh):
                    cur.execute(
                        "INSERT INTO accounts(id, address, balance) VALUES (?,?,?)",
                        (int(row["id"]), row["address"].strip(), int(row["balance"])),
                    )
        con.commit()
    finally:
        con.close()


def err(msg: str, code: int):
    return Response(
        '{"error": ' + json.dumps(msg) + "}", status=code, mimetype="application/json"
    )


@app.get("/health")
def health():
    return jsonify({"status": "ok"})


@app.get("/api/fibonacci")
def fib_route():
    raw = request.args.get("k")
    if raw is None:
        return err("invalid k", 400)
    try:
        k = int(raw)
    except ValueError:
        return err("invalid k", 400)
    if k < 0:
        return err("k must be non-negative", 400)
    if k > 200:
        return err("k out of range", 400)
    return jsonify({"k": k, "value": fib(k)})


def parse_id(s: str):
    try:
        return int(s)
    except ValueError:
        return None


@app.get("/api/status/block/<string:bid>")
def status_block(bid):
    i = parse_id(bid)
    if i is None:
        return err("invalid id", 400)
    if i in CONF_BLOCK:
        status = "confirmed"
    elif i in PEND_BLOCK:
        status = "pending"
    else:
        return err("block not found", 404)
    return jsonify({"type": "block", "id": i, "status": status})


@app.get("/api/status/tx/<string:txid>")
def status_tx(txid):
    i = parse_id(txid)
    if i is None:
        return err("invalid id", 400)
    if i in CONF_TX:
        status = "confirmed"
    elif i in PEND_TX:
        status = "pending"
    else:
        return err("transaction not found", 404)
    return jsonify({"type": "tx", "id": i, "status": status})


@app.get("/api/accounts")
def accounts():
    def getint(v, default):
        if v is None:
            return default
        try:
            iv = int(v)
        except ValueError:
            return -1  # sentinel: invalid
        return iv if iv >= 0 else -1

    off = getint(request.args.get("offset"), 0)
    limit = getint(request.args.get("limit"), None)
    if off == -1 or limit == -1:
        return err("offset and limit must be non-negative integers", 400)

    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    try:
        rows = con.execute(
            "SELECT id, address, balance FROM accounts ORDER BY id"
        ).fetchall()
    finally:
        con.close()

    total = len(rows)
    if limit is None:
        chunk = rows[off:]
    else:
        chunk = rows[off:off + limit]
    result = [
        {"id": r["id"], "address": r["address"], "balance": r["balance"]} for r in chunk
    ]
    return jsonify({"total": total, "result": result})


@app.get("/render")
def render():
    # Neutralize template rendering: the supplied value is emitted as literal
    # plain text, never run through a template engine, never evaluated, never
    # HTML-escaped. The body is exactly the raw input bytes (as text).
    t = request.args.get("text", "")
    return Response(t, mimetype="text/plain")


@app.errorhandler(404)
def _not_found(_e):
    return jsonify({"error": "not found"}), 404


@app.errorhandler(400)
def _bad_request(_e):
    return jsonify({"error": "bad request"}), 400


@app.errorhandler(500)
def _internal_error(_e):
    return jsonify({"error": "internal error"}), 500


if __name__ == "__main__":
    seed()
    print("FATHOM-API-UP 0.0.0.0:8787", flush=True)
    app.run(host="0.0.0.0", port=PORT)
PY

# ---- 2. Start the local fixture server and fetch the remote files byte-for-byte ----
python3 /app/tools/fixture_server.py &
FIX_PID=$!
sleep 2
mkdir -p /app/delivered
python3 - << 'PY'
import requests
mapping = {"alpha": "alpha.bin", "beta": "beta.txt"}
for key, fname in mapping.items():
    r = requests.get(f"http://127.0.0.1:9898/{key}", timeout=10)
    assert r.status_code == 200, (key, r.status_code)
    with open("/app/delivered/" + fname, "wb") as fh:
        fh.write(r.content)
PY
kill "$FIX_PID" 2>/dev/null || true

# Byte-length sanity so a bad fetch is caught immediately.
python3 - << 'PY'
import os
for f, want in (("/app/delivered/alpha.bin", 35), ("/app/delivered/beta.txt", 83)):
    n = os.path.getsize(f)
    assert n == want, (f, n, want)
    print(f, "bytes=", n)
PY

# ---- 3. Start the API server (captures the readiness line to server.out) -------
python3 /app/server.py > /app/server.out 2>&1 &
SERV_PID=$!

python3 - << 'PY'
import json
import time
import requests
ok = False
for _ in range(120):
    try:
        r = requests.get("http://127.0.0.1:8787/health", timeout=1)
        if r.status_code == 200 and r.json().get("status") == "ok":
            ok = True
            break
    except Exception:
        pass
    time.sleep(0.5)
assert ok, "server did not come up"
PY

# ---- 4. Export the DB table to /app/dump.csv (same rows as DB and source) ------
python3 /app/tools/export_csv.py

echo "solution done"
exit 0