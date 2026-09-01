#!/bin/bash
# Oracle for opal-marsh: write the generator, then RUN it on the shipped spec to
# produce /app/calib_map.txt and /app/map_report.json. Never reads /tests.
set -eu

cat > /app/gen_map.py <<'PY'
#!/usr/bin/env python3
"""Emit the Opal Marsh calibration permutation under row and byte caps."""
import argparse
import json
import os
import sys


def rotl(x, r, bits):
    r %= bits
    if r == 0:
        return x
    return ((x << r) | (x >> (bits - r))) & ((1 << bits) - 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("out", nargs="?", default="/app/calib_map.txt")
    ap.add_argument("--report-out", default="/app/map_report.json")
    args = ap.parse_args()

    with open(args.spec, "r", encoding="utf-8") as fh:
        spec = json.load(fh)
    bits = int(spec["bits"])
    a = int(spec["a"])
    r = int(spec["r"])
    cap_rows = int(spec["cap_rows"])
    cap_bytes = int(spec["cap_bytes"])

    n = 1 << bits
    w = (bits + 3) // 4
    m = [rotl(s ^ a, r, bits) for s in range(n)]

    row_len = 2 * w + 2                      # 'srchex,dsthex\n'
    full_rows = n
    full_bytes = 5 + full_rows * row_len     # 'FULL\n'
    exceptions = [s for s in range(n) if m[s] != s]
    sparse_rows = len(exceptions)
    sparse_bytes = 7 + sparse_rows * row_len  # 'SPARSE\n'

    ok_full = full_rows <= cap_rows and full_bytes <= cap_bytes
    ok_sparse = sparse_rows <= cap_rows and sparse_bytes <= cap_bytes

    if not ok_full and not ok_sparse:
        print("INFEASIBLE: no encoding fits cap_rows=%d cap_bytes=%d "
              "(FULL needs %d rows/%d bytes, SPARSE needs %d rows/%d bytes)"
              % (cap_rows, cap_bytes, full_rows, full_bytes,
                 sparse_rows, sparse_bytes))
        sys.exit(2)

    if ok_full and ok_sparse:
        mode = "FULL" if full_bytes <= sparse_bytes else "SPARSE"
    elif ok_full:
        mode = "FULL"
    else:
        mode = "SPARSE"

    if mode == "FULL":
        lines = ["FULL"]
        for s in range(n):
            lines.append("%0*x,%0*x" % (w, s, w, m[s]))
        rows = full_rows
    else:
        lines = ["SPARSE"]
        for s in exceptions:
            lines.append("%0*x,%0*x" % (w, s, w, m[s]))
        rows = sparse_rows

    data = ("\n".join(lines) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(args.out))
    os.makedirs(out_dir, exist_ok=True)
    with open(args.out, "wb") as fh:
        fh.write(data)
    nbytes = len(data)

    report = {"mode": mode, "mapping_rows": rows, "file_bytes": nbytes}
    rep_dir = os.path.dirname(os.path.abspath(args.report_out))
    os.makedirs(rep_dir, exist_ok=True)
    with open(args.report_out, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")
    print("mode=%s rows=%d bytes=%d" % (mode, rows, nbytes))


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/gen_map.py

python3 /app/gen_map.py /app/spec.json

echo "solve.sh done"
ls -l /app/gen_map.py /app/calib_map.txt /app/map_report.json
head -3 /app/calib_map.txt
cat /app/map_report.json
