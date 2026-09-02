#!/bin/bash
# Oracle for mist-buoy: write the contract-driven client, ensure the visible
# archive instance is up, then RUN the client against it to produce
# /app/report.json. Never reads /tests.
set -eu

CLIENT="/app/client.py"
OUT="/app/report.json"
PORT=8098

cat > "$CLIENT" <<'PY'
#!/usr/bin/env python3
"""Mist Buoy archive client: reads the hosted contract, then follows it.

Usage: python3 client.py <base_url> <output_json>
"""
import json
import sys
import time
import urllib.error
import urllib.request


def call(url, method="GET", obj=None, headers=None):
    data = json.dumps(obj).encode() if obj is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode() or "{}"
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {}


def main():
    base, out_path = sys.argv[1].rstrip("/"), sys.argv[2]

    # 1. Discover the contract from the hosted doc.
    st, doc = call(base + "/contract.json")
    if st != 200:
        raise SystemExit("contract fetch failed: %s" % st)
    auth = doc["auth"]
    hdr = {auth["header"]: auth["value"]}
    campaign = doc["campaign"]

    # 2. Page through all stations.
    stations, cursor = [], None
    while True:
        q = "/api/v2/stations?limit=8"
        if cursor:
            q += "&cursor=" + cursor
        st, body = call(base + q, headers=hdr)
        if st != 200:
            raise SystemExit("stations fetch failed: %s %s" % (st, body))
        stations.extend(body["stations"])
        cursor = body["next_cursor"]
        if not cursor:
            break

    # 3. Select stations per the campaign rule.
    selected = [s["id"] for s in stations
                if s["status"] == campaign["select_status"]]

    # 4. Request the report job.
    st, body = call(
        base + "/api/v2/reports", method="POST",
        obj={"station_ids": selected, "metric": campaign["metric"],
             "window": campaign["window"]},
        headers=hdr)
    if st != 202:
        raise SystemExit("report submit failed: %s %s" % (st, body))
    job_id = body["job_id"]

    # 5. Poll until done.
    result = None
    for _ in range(60):
        st, body = call(base + "/api/v2/reports/" + job_id, headers=hdr)
        if st != 200:
            raise SystemExit("poll failed: %s %s" % (st, body))
        if body["status"] == "done":
            result = body["result"]
            break
        time.sleep(0.1)
    if result is None:
        raise SystemExit("report never completed")

    out = {
        "contract_version": doc["contract_version"],
        "stations_total": len(stations),
        "stations_selected": len(selected),
        "report": result,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$CLIENT"

# Ensure the visible instance is serving on 8098 (start it if it is not).
python3 - "$PORT" <<'PY'
import subprocess, sys, time, urllib.request
port = sys.argv[1]
def up():
    try:
        with urllib.request.urlopen("http://127.0.0.1:%s/contract.json" % port, timeout=2) as r:
            return r.status == 200
    except Exception:
        return False
if not up():
    subprocess.Popen(
        ["python3", "/app/server.py", "/app/data/visible.json", port],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        if up():
            break
        time.sleep(0.2)
    else:
        raise SystemExit("could not start visible archive instance")
PY

python3 "$CLIENT" "http://127.0.0.1:$PORT" "$OUT"

echo "solve.sh done -> $CLIENT and $OUT"
ls -l "$CLIENT" "$OUT"
