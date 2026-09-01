#!/bin/bash
# Brine Cipher oracle. Writes the deliverable de-envelope tool /app/dewal.py,
# runs it on the visible envelope to restore /app/gauge.db-wal, reads the
# committed WAL rows through an isolated copy, and writes /app/answer.txt.
# Never reads /tests.
set -eu

cat > /app/dewal.py <<'PY'
#!/usr/bin/env python3
"""De-envelope an XOR-obfuscated SQLite WAL and restore the valid original."""
import struct
import sys

MAGICS = (b"\x37\x7f\x06\x82", b"\x37\x7f\x06\x83")


def main(argv):
    if len(argv) != 3:
        print("usage: dewal.py <enc_path> <out_wal_path>", file=sys.stderr)
        return 2
    enc_path, out_path = argv[1], argv[2]
    enc = open(enc_path, "rb").read()

    if enc[:7] != b"ENCWAL1":
        print("bad envelope magic", file=sys.stderr)
        return 1
    if enc[7] != 1:
        print("unsupported version %d" % enc[7], file=sys.stderr)
        return 1
    payload_len, _reserved = struct.unpack_from("<II", enc, 8)
    payload = enc[16:]
    if len(payload) != payload_len:
        print("payload_len mismatch", file=sys.stderr)
        return 1

    # pin the single-byte XOR key from the WAL magic's first three bytes
    k0 = payload[0] ^ 0x37
    k1 = payload[1] ^ 0x7F
    k2 = payload[2] ^ 0x06
    if not (k0 == k1 == k2):
        print("no consistent XOR key", file=sys.stderr)
        return 1
    key = k0
    if payload[3] ^ key not in (MAGICS[0][3], MAGICS[1][3]):
        print("magic check failed", file=sys.stderr)
        return 1

    wal = bytes(b ^ key for b in payload)
    assert wal[:4] in MAGICS
    with open(out_path, "wb") as fh:
        fh.write(wal)
    print("KEY=%d" % key)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod +x /app/dewal.py

# Restore the valid WAL for the visible database.
python3 /app/dewal.py /app/gauge.db-wal.enc /app/gauge.db-wal

# Read the committed WAL rows through an isolated copy (never touch /app files).
WORK=$(mktemp -d)
cp /app/gauge.db "$WORK/g.db"
cp /app/gauge.db-wal "$WORK/g.db-wal"
python3 - "$WORK/g.db" /app/answer.txt <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
rows = list(con.execute("SELECT level_mm FROM gauge_readings"))
peak = max(r[0] for r in rows)
with open(sys.argv[2], "w") as fh:
    fh.write("max_level=%d\n" % peak)
print("answer:", peak)
PY
rm -rf "$WORK"

echo "solve.sh done"
ls -l /app/dewal.py /app/gauge.db-wal /app/answer.txt
