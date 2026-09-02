#!/bin/bash
# Real oracle for cinder-reef: write the fret_client.py deliverable, then RUN
# it on the visible fixtures to produce /app/fret_report.json. Never reads /tests.
set -eu

CLIENT="/app/fret_client.py"
OUT="/app/fret_report.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$CLIENT" <<'PY'
#!/usr/bin/env python3
"""FRET donor/acceptor selection client for the Ember Biosciences spectra API.

Contract:
    python3 /app/fret_client.py <data_dir> <out.json>

Starts /app/spectra_server.py serving <data_dir>/api.json on a free 127.0.0.1
port, polls /health until ready, enumerates proteins, fetches each spectra
payload (skipping 404s for retired/unknown ids), and applies the FRET spec:
  - donor    = unique protein with emission_nm in [emission_min, emission_max]
  - acceptor = unique protein with excitation_nm in [excitation_min,
               excitation_max] and 0 <= donor.emission_nm - excitation_nm
               <= max_gap_nm
Writes {"donor", "acceptor", "gap_nm"} to <out.json>.
"""
import json
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

SERVER = "/app/spectra_server.py"


def free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def get_json(base, path, timeout=10.0):
    """GET base+path; return (status, parsed-or-None)."""
    url = base + path
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, None


def main():
    data_dir, out_path = sys.argv[1], sys.argv[2]
    with open(f"{data_dir}/spec.json", "r", encoding="utf-8") as fh:
        spec = json.load(fh)

    port = free_port()
    base = f"http://127.0.0.1:{port}"
    proc = subprocess.Popen(
        ["python3", SERVER, f"{data_dir}/api.json", str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        # readiness poll
        deadline = time.time() + 20.0
        while time.time() < deadline:
            if proc.poll() is not None:
                raise RuntimeError("spectra server exited early")
            try:
                status, body = get_json(base, "/health", timeout=2.0)
                if status == 200 and body.get("ok"):
                    break
            except OSError:
                pass
            time.sleep(0.1)
        else:
            raise RuntimeError("spectra server did not become ready")

        status, listing = get_json(base, "/api/proteins")
        if status != 200:
            raise RuntimeError("failed to list proteins")

        spectra = {}
        for entry in listing["proteins"]:
            pid = entry["id"]
            st, payload = get_json(base, f"/api/spectra?id={pid}")
            if st != 200:
                continue  # retired or unknown: skip
            spectra[pid] = payload

        donor_band = spec["donor"]
        acc_band = spec["acceptor"]
        max_gap = spec["max_gap_nm"]

        donors = [p for p in spectra.values()
                  if donor_band["emission_min"] <= p["emission_nm"]
                  <= donor_band["emission_max"]]
        if len(donors) != 1:
            raise RuntimeError("expected exactly one donor, got %d" % len(donors))
        donor = donors[0]

        acceptors = []
        for p in spectra.values():
            if not (acc_band["excitation_min"] <= p["excitation_nm"]
                    <= acc_band["excitation_max"]):
                continue
            gap = donor["emission_nm"] - p["excitation_nm"]
            if 0 <= gap <= max_gap:
                acceptors.append(p)
        if len(acceptors) != 1:
            raise RuntimeError("expected exactly one acceptor, got %d" % len(acceptors))
        acceptor = acceptors[0]

        report = {
            "donor": donor,
            "acceptor": acceptor,
            "gap_nm": donor["emission_nm"] - acceptor["excitation_nm"],
        }
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=2)
            fh.write("\n")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    sys.exit(0)


if __name__ == "__main__":
    main()
PY

chmod +x "$CLIENT"

# 2. Run the produced client on the visible fixtures to generate the report.
python3 "$CLIENT" /app/db "$OUT"

echo "solve.sh done -> $CLIENT and $OUT"
ls -l "$CLIENT" "$OUT"
