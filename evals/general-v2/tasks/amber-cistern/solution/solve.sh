#!/bin/bash
# Real oracle for amber-cistern: author the probe client, boot the slotd
# service on the visible table, drive the protocol, and produce the visible
# summary. Never reads /tests.
set -euo pipefail
cd /app

PROBE="/app/probe.py"
SUMMARY="/app/summary.json"
TABLE="/app/registry/table.json"
MANIFEST="/app/registry/manifest.txt"
PORT=47331

# ---- 1. Deliverable /app/probe.py : the socket probe client ----
cat > "$PROBE" <<'PY'
import hashlib
import json
import re
import socket
import sys

PROBE_RE = re.compile(r"^\s*SLOT\s+([A-Z]{1,8}/[0-9]+/[0-9]+)\s*$")


def query(host, port, key):
    """One request per connection, per the strict single-request-per-turn
    discipline: connect, send one line, read one JSON line, close."""
    s = socket.create_connection((host, port), timeout=10)
    try:
        s.sendall(("SLOT " + key + "\n").encode("utf-8"))
        buf = b""
        while not buf.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        line = buf.decode("utf-8", "replace").strip()
        return json.loads(line)
    finally:
        s.close()


def main():
    host, port, manifest_path, out_path = (
        sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4])
    keys = []
    seen = set()
    with open(manifest_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            if raw.lstrip().startswith("#"):
                continue
            m = PROBE_RE.match(raw.rstrip("\n"))
            if not m:
                continue
            k = m.group(1)
            if k not in seen:
                seen.add(k)
                keys.append(k)

    ok_slots, unknown, tokens = [], [], {}
    total_qty = 0
    heaviest = None
    for k in keys:
        try:
            resp = query(host, port, k)
        except Exception:
            continue
        if resp.get("ok") is True and resp.get("kind") == "slot":
            ok_slots.append(k)
            tokens[k] = resp["token"]
            total_qty += int(resp["qty"])
            cand = {"slot": k, "sku": resp["sku"], "qty": int(resp["qty"]),
                    "token": resp["token"]}
            if heaviest is None or cand["qty"] > heaviest["qty"] or (
                    cand["qty"] == heaviest["qty"] and k < heaviest["slot"]):
                heaviest = cand
        elif resp.get("error") == "unknown-slot":
            unknown.append(k)

    summary = {
        "ok_slots": sorted(ok_slots),
        "unknown": sorted(unknown),
        "tokens": {k: tokens[k] for k in sorted(tokens)},
        "total_qty": total_qty,
        "heaviest": heaviest,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2, sort_keys=True)


if __name__ == "__main__":
    main()
PY
chmod 0755 "$PROBE"

# ---- 2. Boot the visible slotd instance on loopback:47331 ----
pkill -f "slotd.py $TABLE" 2>/dev/null || true
sleep 0.2
python3 /app/registry/slotd.py "$TABLE" "$PORT" > /tmp/oracle_slotd.log 2>&1 &
SLOTD_PID=$!
sleep 1.0

# ---- 3. Run the probe client to produce the visible summary ----
python3 "$PROBE" 127.0.0.1 "$PORT" "$MANIFEST" "$SUMMARY"

kill "$SLOTD_PID" 2>/dev/null || true

echo "solve.sh done -> $PROBE and $SUMMARY"
cat "$SUMMARY"
