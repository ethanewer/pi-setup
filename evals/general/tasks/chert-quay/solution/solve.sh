#!/bin/bash
# Oracle for chert-quay: write the salvage program, then RUN it on the visible
# fixture to produce /app/salvaged.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/salvaged.json"

cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Diagnose truncation of a SQLite scan database and salvage intact rows."""
import json
import sqlite3
import struct
import sys


def read_header(b):
    if len(b) < 100 or b[:16] != b"SQLite format 3\x00":
        raise ValueError("not a valid SQLite 3 database header")
    ps = struct.unpack(">H", b[16:18])[0]
    ps = 65536 if ps == 1 else ps
    hpc = struct.unpack(">I", b[28:32])[0]
    return ps, hpc


def classify(size, ps, hpc):
    if size >= hpc * ps:
        return "intact"
    if size % ps == 0:
        return "page_aligned"
    return "mid_page"


def salvage(db_path):
    b = open(db_path, "rb").read()
    ps, hpc = read_header(b)
    size = len(b)
    present = size // ps
    mode = classify(size, ps, hpc)

    padded = b if size >= hpc * ps else b + b"\x00" * (hpc * ps - size)
    tmp = "/tmp/_chert_quay_padded_copy.db"
    with open(tmp, "wb") as fh:
        fh.write(padded)

    con = sqlite3.connect("file:%s?mode=ro" % tmp, uri=True)
    cur = con.cursor()
    rows = []
    misses = 0
    i = 1
    while misses < 1000 and i <= 200000:
        r = None
        try:
            r = cur.execute(
                "SELECT id, pallet, lane, gross_kg, scanned_at "
                "FROM scan WHERE id = ?",
                (i,),
            ).fetchone()
        except sqlite3.DatabaseError:
            r = None
        if (
            r is not None
            and isinstance(r[0], int)
            and isinstance(r[1], str)
            and isinstance(r[2], int)
            and isinstance(r[3], (int, float))
            and isinstance(r[4], str)
        ):
            rows.append(
                {
                    "id": r[0],
                    "pallet": r[1],
                    "lane": r[2],
                    "gross_kg": float(r[3]),
                    "scanned_at": r[4],
                }
            )
            misses = 0
        else:
            misses += 1
        i += 1
    con.close()

    report = {
        "file": {
            "page_size": ps,
            "header_page_count": hpc,
            "present_page_count": present,
            "file_bytes": size,
        },
        "truncation": {
            "mode": mode,
            "missing_bytes": max(0, hpc * ps - size),
        },
        "salvaged_rows": rows,
    }
    return report


def main():
    db_path, out_path = sys.argv[1], sys.argv[2]
    report = salvage(db_path)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/corrupt.db "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
