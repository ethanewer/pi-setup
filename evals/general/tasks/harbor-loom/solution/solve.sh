#!/bin/bash
# Oracle for harbor-loom: writes the deliverable client under /app, then RUNS
# it on the visible fixtures to produce /app/sequences_out.json. Never reads /tests.
set -euo pipefail

SOLVER="/app/seqfetch.py"
OUT="/app/sequences_out.json"

# ---- deliverable: /app/seqfetch.py ----
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Harbor Point structural-genomics sequence fetcher.

    python3 /app/seqfetch.py <data_dir> <out.json>

Starts the localhost mock structure API on a free port, resolves each
"<ACCESSION>.<CHAIN>" identifier (uppercasing, following obsolete
supersession chains), fetches the wrapped sequence, verifies the sha256
checksum, and reports sequences keyed by the original identifier.
"""
import hashlib
import json
import socket
import subprocess
import sys
import time
import urllib.error
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
    db_path = data_dir.rstrip("/") + "/db.json"
    requests_path = data_dir.rstrip("/") + "/requests.json"

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
                raise RuntimeError("structure API did not become healthy")
            time.sleep(0.1)

        with open(requests_path, "r", encoding="utf-8") as fh:
            spec = json.load(fh)

        def resolve(acc):
            """Follow obsolete -> superseded_by until a current entry."""
            while True:
                ent = get_json("%s/api/entries/%s" % (base, acc))
                if ent["status"] == "current":
                    return acc
                acc = ent["superseded_by"].upper()

        sequences = {}
        checksum_failures = []
        for orig_id in spec["requests"]:
            acc, _, chain = orig_id.rpartition(".")
            acc = acc.upper()
            chain = chain.upper()
            cur = resolve(acc)
            payload = get_json("%s/api/sequences/%s/%s" % (base, cur, chain))
            seq = "".join(payload["lines"])
            if hashlib.sha256(seq.encode()).hexdigest() != payload["sha256"]:
                checksum_failures.append(orig_id)
            sequences[orig_id] = seq

        report = {
            "sequences": sequences,
            "checksum_failures": sorted(checksum_failures),
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

# ---- visible run: produce /app/sequences_out.json from the live fixtures ----
python3 "$SOLVER" /app/data "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
