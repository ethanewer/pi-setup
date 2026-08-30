#!/usr/bin/env python3
"""Grove LUT generator: complete substitution table under entry/byte caps.

usage: gen-table.py <spec.json> [out.csv]

spec.json: {"bits": int, "a": int, "b": int, "cap_rows": int, "cap_bytes": int}
Writes "src,dst" rows for every src in [0, 2**bits): dst = (a*src + b) mod 2**bits.
'a' must be odd so the map is a bijection (complete table, no repeats).
"""
import json
import sys


def main() -> int:
    with open(sys.argv[1]) as fh:
        spec = json.load(fh)
    out = sys.argv[2] if len(sys.argv) > 2 else "/app/table.csv"
    bits = int(spec["bits"])
    a, b = int(spec["a"]), int(spec["b"])
    cap_rows = int(spec["cap_rows"])
    cap_bytes = int(spec["cap_bytes"])
    mod = 1 << bits

    rows = []
    for src in range(mod):
        dst = (a * src + b) % mod
        rows.append("%02X,%02X\n" % (src, dst))
    size = sum(len(r) for r in rows)
    if len(rows) > cap_rows or size > cap_bytes:
        print("OVER_LIMIT %d rows %d bytes (caps %d/%d)" % (len(rows), size, cap_rows, cap_bytes))
        return 1
    with open(out, "w") as fh:
        fh.writelines(rows)
    print("wrote %d rows, %d bytes (caps %d/%d)" % (len(rows), size, cap_rows, cap_bytes))
    return 0


if __name__ == "__main__":
    sys.exit(main())