#!/bin/bash
# Real oracle for moor-latch: write the struct_client.py deliverable, then RUN
# it on the visible fixtures to produce /app/struct_report.json. Never reads /tests.
set -eu

CLIENT="/app/struct_client.py"
OUT="/app/struct_report.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$CLIENT" <<'PY'
#!/usr/bin/env python3
"""Moorfield structure-archive client.

Contract:
    python3 /app/struct_client.py <data_dir> <out.json>

Starts /app/structure_server.py serving <data_dir>/entries.json on a free
127.0.0.1 port, polls /health until ready, then for each entry id in
<data_dir>/spec.json fetches entry metadata (/api/entry/<id>) and, for every
listed chain, the verbatim amino-acid sequence (/api/sequence/<eid>/<cid>).
Writes {"entries": {...}, "total_chains": N, "total_residues": M} to <out.json>.
"""
import json
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

SERVER = "/app/structure_server.py"


def free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def get_json(base, path, timeout=10.0):
    """GET base+path; return (status, parsed-or-None)."""
    try:
        with urllib.request.urlopen(base + path, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, None


def main():
    data_dir, out_path = sys.argv[1], sys.argv[2]
    with open(f"{data_dir}/spec.json", "r", encoding="utf-8") as fh:
        spec = json.load(fh)
    entry_ids = spec["entry_ids"]

    port = free_port()
    base = f"http://127.0.0.1:{port}"
    proc = subprocess.Popen(
        ["python3", SERVER, f"{data_dir}/entries.json", str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.time() + 20.0
        while time.time() < deadline:
            if proc.poll() is not None:
                raise RuntimeError("structure server exited early")
            try:
                status, body = get_json(base, "/health", timeout=2.0)
                if status == 200 and body.get("ok"):
                    break
            except OSError:
                pass
            time.sleep(0.1)
        else:
            raise RuntimeError("structure server did not become ready")

        entries = {}
        total_chains = 0
        total_residues = 0
        for eid in entry_ids:
            status, meta = get_json(base, "/api/entry/%s" % eid)
            if status != 200:
                raise RuntimeError("entry %s: HTTP %s" % (eid, status))
            chains = {}
            for ch in meta["chains"]:
                cid = ch["chain_id"]
                st, payload = get_json(base, "/api/sequence/%s/%s" % (eid, cid))
                if st != 200:
                    raise RuntimeError("chain %s/%s: HTTP %s" % (eid, cid, st))
                chains[cid] = payload["sequence"]
                total_residues += len(payload["sequence"])
                total_chains += 1
            entries[eid] = chains

        report = {
            "entries": entries,
            "total_chains": total_chains,
            "total_residues": total_residues,
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
