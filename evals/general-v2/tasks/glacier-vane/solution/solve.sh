#!/bin/bash
# Oracle for glacier-vane: writes the deliverable client under /app, then RUNS
# it on the visible fixtures to produce /app/spectra_report.json. Never reads /tests.
set -euo pipefail

SOLVER="/app/spectra_client.py"
OUT="/app/spectra_report.json"

# ---- deliverable: /app/spectra_client.py ----
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Glacier Ridge microscopy-core spectra client.

    python3 /app/spectra_client.py <data_dir> <out.json>

Starts the localhost mock spectra API on a free port, pages through the
spectral catalog, applies the channel selection rules (status, laser
tolerance, emission band, brightness floor, then brightness/id tie-break),
and writes the calibration report.
"""
import json
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SERVER = "/app/api_server.py"


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def get_json(url):
    with urllib.request.urlopen(url, timeout=10) as resp:
        return json.loads(resp.read().decode())


def main():
    data_dir, out_path = sys.argv[1], sys.argv[2]
    db_path = data_dir.rstrip("/") + "/proteins.json"
    channels_path = data_dir.rstrip("/") + "/channels.json"

    port = free_port()
    proc = subprocess.Popen(
        [sys.executable, SERVER, db_path, str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        base = "http://127.0.0.1:%d" % port
        deadline = time.time() + 30
        while True:
            try:
                if get_json(base + "/health").get("ok"):
                    break
            except Exception:
                pass
            if time.time() > deadline:
                raise RuntimeError("spectra API did not become healthy")
            time.sleep(0.1)

        # 1. Page through the full spectral catalog (server caps per_page at 5).
        items = []
        page = 1
        total = None
        while True:
            payload = get_json(
                "%s/api/spectra?page=%d&per_page=5" % (base, page))
            total = payload["total"]
            items.extend(payload["items"])
            if len(items) >= total or not payload["items"]:
                break
            page += 1
        by_id = {it["id"]: it for it in items}

        # 2. Status lookup (withdrawn proteins are excluded).
        statuses = {}
        for pid in by_id:
            statuses[pid] = get_json(
                "%s/api/status?id=%s" % (base, urllib.parse.quote(pid)))["status"]

        # 3. Apply the channel selection rules.
        with open(channels_path, "r", encoding="utf-8") as fh:
            spec = json.load(fh)

        report_channels = {}
        unassigned = []
        for ch in spec["channels"]:
            cands = [
                it for it in items
                if statuses.get(it["id"]) == "active"
                and abs(it["excitation_nm"] - ch["laser_nm"]) <= ch["laser_tolerance_nm"]
                and ch["emission_min"] <= it["emission_nm"] <= ch["emission_max"]
                and it["brightness"] >= ch["min_brightness"]
            ]
            if not cands:
                unassigned.append(ch["channel"])
                continue
            best = sorted(cands, key=lambda it: (-it["brightness"], it["id"]))[0]
            report_channels[ch["channel"]] = {
                "protein_id": best["id"],
                "excitation_nm": best["excitation_nm"],
                "emission_nm": best["emission_nm"],
                "brightness": best["brightness"],
            }

        report = {
            "channels": report_channels,
            "unassigned_channels": sorted(unassigned),
        }
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
            fh.write("\n")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    main()
PY
chmod +x "$SOLVER"

# ---- visible run: produce /app/spectra_report.json from the live fixtures ----
python3 "$SOLVER" /app/data "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
