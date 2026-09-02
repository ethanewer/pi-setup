#!/bin/bash
# Real oracle for umber-flotilla: implement the portfolio service, start it,
# POST the visible fixture, and save the live summary to /app/summary.json.
# Never reads /tests.
set -eu

SERVICE="/app/service.py"
SUMMARY="/app/summary.json"
FIXTURE="/app/portfolio_visible.json"
PORT=8100

cat > "$SERVICE" <<'PY'
"""Umber Flotilla fund-administration portfolio ingest service."""
import json
import math
import sys
from flask import Flask, jsonify, request

app = Flask(__name__)
_STORE = {}          # id -> {"order": [...], "assets": {...}}
_INSERTION = []      # insertion order of portfolio ids
TOP_N = 10


def _bad(msg):
    return jsonify({"error": {"code": "bad_request", "message": msg}}), 400


def _num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) \
        and math.isfinite(x)


def _validate(body):
    if not isinstance(body, dict):
        return "body must be a JSON object"
    pid = body.get("id")
    if not isinstance(pid, str) or not pid:
        return "id must be a non-empty string"
    assets = body.get("assets")
    if not isinstance(assets, list):
        return "assets must be a list"
    seen = set()
    for a in assets:
        if not isinstance(a, dict):
            return "each asset must be a JSON object"
        for k in ("id", "sector", "quantity", "unit_price"):
            if k not in a:
                return "asset missing key %r" % k
        if not isinstance(a["id"], str) or not a["id"]:
            return "asset id must be a non-empty string"
        if not isinstance(a["sector"], str) or not a["sector"]:
            return "asset sector must be a non-empty string"
        if not _num(a["quantity"]) or not _num(a["unit_price"]):
            return "asset quantity/unit_price must be finite numbers"
        if a["id"] in seen:
            return "duplicate asset id %r" % a["id"]
        seen.add(a["id"])
    return None


def _summary(pid):
    entry = _STORE[pid]
    total = 0.0
    sectors = {}
    vals = []
    for a in entry["order"]:
        v = a["quantity"] * a["unit_price"]
        total += v
        s = a["sector"]
        b = sectors.get(s)
        if b is None:
            b = sectors[s] = {"count": 0, "value": 0.0}
        b["count"] += 1
        b["value"] += v
        vals.append((a["id"], v))
    if total != 0:
        out_sectors = {s: {"count": sectors[s]["count"],
                           "value": sectors[s]["value"],
                           "weight": sectors[s]["value"] / total}
                       for s in sectors}
    else:
        out_sectors = {s: {"count": sectors[s]["count"],
                           "value": sectors[s]["value"],
                           "weight": 0.0} for s in sectors}
    top = sorted(vals, key=lambda t: (-t[1], t[0]))[:TOP_N]
    return {
        "id": pid,
        "asset_count": len(entry["order"]),
        "total_value": total,
        "sectors": out_sectors,
        "top": [{"id": i, "value": v} for i, v in top],
    }


@app.post("/api/v1/portfolios")
def post_portfolio():
    body = request.get_json(silent=True)
    err = _validate(body)
    if err is not None:
        return _bad(err)
    pid = body["id"]
    if pid not in _STORE:
        _INSERTION.append(pid)
    _STORE[pid] = {"order": body["assets"]}
    return jsonify({"id": pid, "asset_count": len(body["assets"])}), 201


@app.get("/api/v1/portfolios")
def list_portfolios():
    return jsonify({"count": len(_INSERTION),
                    "portfolios": [{"id": p, "asset_count": len(_STORE[p]["order"])}
                                   for p in _INSERTION]})


@app.get("/api/v1/portfolios/<pid>/summary")
def get_summary(pid):
    if pid not in _STORE:
        return jsonify({"error": {"code": "not_found", "id": pid,
                                  "message": "no such portfolio"}}), 404
    return jsonify(_summary(pid))


@app.get("/api/v1/health")
def health():
    return jsonify({"status": "ok"})


@app.errorhandler(404)
def not_found(_e):
    return jsonify({"error": {"code": "not_found",
                              "message": "no such route"}}), 404


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8100
    app.run(host="127.0.0.1", port=port, threaded=True)
PY
chmod +x "$SERVICE"

# Start the service, drive it with the visible fixture, save the summary.
python3 "$SERVICE" "$PORT" >/tmp/umber_service.log 2>&1 &
SVC_PID=$!
trap 'kill "$SVC_PID" 2>/dev/null || true' EXIT

python3 - "$PORT" "$FIXTURE" "$SUMMARY" <<'PY'
import json, sys, time, urllib.request

port, fixture, out_path = int(sys.argv[1]), sys.argv[2], sys.argv[3]
base = "http://127.0.0.1:%d" % port

deadline = time.time() + 20
while True:
    try:
        with urllib.request.urlopen(base + "/api/v1/health", timeout=2) as r:
            if r.status == 200:
                break
    except Exception:
        if time.time() > deadline:
            raise RuntimeError("service did not come up")
        time.sleep(0.2)

with open(fixture) as f:
    payload = json.load(f)
req = urllib.request.Request(base + "/api/v1/portfolios",
                             data=json.dumps(payload).encode(),
                             headers={"Content-Type": "application/json"},
                             method="POST")
with urllib.request.urlopen(req, timeout=60) as r:
    assert r.status == 201, r.status

with urllib.request.urlopen(base + "/api/v1/portfolios/visible-fleet/summary",
                            timeout=60) as r:
    summary = json.load(r)
with open(out_path, "w") as f:
    json.dump(summary, f, indent=2)
print("summary written:", out_path)
PY

kill "$SVC_PID" 2>/dev/null || true
wait "$SVC_PID" 2>/dev/null || true
trap - EXIT
echo "solve.sh done -> $SERVICE and $SUMMARY"
ls -l "$SERVICE" "$SUMMARY"
