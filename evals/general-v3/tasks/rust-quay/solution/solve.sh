#!/bin/bash
# Real oracle for rust-quay: write the general dewal.py tool (this IS the
# work, not a canned answer), decode the visible obfuscated WAL into
# /app/quay.db-wal, then extract /app/secrets.json. Never reads /tests.
set -eu

TOOL="/app/dewal.py"

# ---- 1. Write the general WAL de-obfuscation / extraction tool.
cat > "$TOOL" <<'PY'
#!/usr/bin/env python3
"""Quay WAL de-obfuscation and secret-extraction tool.

Usage:
    python3 dewal.py decode <enc_wal> <out_wal>
    python3 dewal.py extract <db_path> <out_json>

decode: <enc_wal> is a real SQLite WAL whose every byte was XOR'd with one
unknown one-byte key.  The key is the unique byte that makes the decoded
header magic valid (37 7f 06 82 or 37 7f 06 83).  Writes the decoded WAL to
<out_wal> and prints KEY=<k> (decimal).

extract: opens a database (which may have committed-but-uncheckpointed frames
in a companion <db_path>-wal) and dumps the quay_secrets table as a JSON
object {name: value}, keys sorted.  Works on a temp copy so the source files
are never checkpointed or modified.
"""
import json
import os
import shutil
import sqlite3
import sys
import tempfile

WAL_MAGICS = (b"\x37\x7f\x06\x82", b"\x37\x7f\x06\x83")


def find_key(enc):
    for k in range(256):
        head = bytes(b ^ k for b in enc[0:4])
        if head in WAL_MAGICS:
            return k
    raise SystemExit("no single-byte key yields a valid WAL magic")


def decode(enc_path, out_path):
    with open(enc_path, "rb") as f:
        enc = f.read()
    if len(enc) < 32:
        raise SystemExit("enc file too short to be a WAL")
    k = find_key(enc)
    out = bytes(b ^ k for b in enc)
    with open(out_path, "wb") as f:
        f.write(out)
    print("KEY=%d" % k)
    return k


def extract(db_path, out_json):
    db_path = os.path.abspath(db_path)
    tmp = tempfile.mkdtemp(prefix="dewal-")
    try:
        work_db = os.path.join(tmp, "data.db")
        shutil.copy(db_path, work_db)
        wal = db_path + "-wal"
        if os.path.exists(wal):
            shutil.copy(wal, work_db + "-wal")
        con = sqlite3.connect(work_db)
        try:
            rows = con.execute(
                "SELECT name, value FROM quay_secrets ORDER BY name"
            ).fetchall()
        finally:
            con.close()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    data = {str(name): str(value) for name, value in rows}
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
    for name in sorted(data):
        print("%s=%s" % (name, data[name]))


def main(argv):
    if len(argv) >= 4 and argv[1] == "decode":
        decode(argv[2], argv[3])
        return 0
    if len(argv) >= 4 and argv[1] == "extract":
        extract(argv[2], argv[3])
        return 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod +x "$TOOL"

# ---- 2. Decode the visible obfuscated WAL into the deliverable WAL.
python3 "$TOOL" decode /app/quay.db-wal.enc /app/quay.db-wal

# ---- 3. Extract the never-checkpointed secrets into the deliverable JSON.
python3 "$TOOL" extract /app/quay.db /app/secrets.json

echo "solve.sh done -> $TOOL, /app/quay.db-wal, /app/secrets.json"
ls -l /app/quay.db-wal /app/secrets.json
