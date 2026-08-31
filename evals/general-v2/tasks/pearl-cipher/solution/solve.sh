#!/bin/bash
# Oracle for pearl-cipher: author /app/crack.py (numpy bulk search over the
# full 30-bit block space) and produce /app/secret.json for the visible
# key/target. Never reads /tests.
set -euo pipefail

cat > /app/crack.py <<'PY'
#!/usr/bin/env python3
"""crack.py KEY_HEX TARGET_HEX OUT_JSON — recover the Pearl32 preimage.

Reimplements the Pearl32 round function with numpy uint32 arrays and streams
the whole 30-bit block space through it in chunks until the target matches.
"""
import json
import sys

import numpy as np

M32 = np.uint32(0xFFFFFFFF)
SHIFT15 = np.uint32(15)
MASK15 = np.uint32(0x7FFF)
SHIFT9 = np.uint32(9)
SHIFT11 = np.uint32(11)
C1 = np.uint32(0x045D9F3B)
SPACE = 1 << 30
CHUNK = 1 << 25


def round_key(K, i):
    z = (K ^ (0x9E3779B9 * i)) & 0xFFFFFFFF
    z ^= z >> 16
    z = (z * 0x85EBCA6B) & 0xFFFFFFFF
    z ^= z >> 13
    z = (z * 0xC2B2AE35) & 0xFFFFFFFF
    z ^= z >> 16
    return z


def main():
    if len(sys.argv) != 4:
        print("usage: crack.py KEY_HEX TARGET_HEX OUT_JSON", file=sys.stderr)
        return 2
    K = int(sys.argv[1], 16) & 0xFFFFFFFF
    T = int(sys.argv[2], 16)
    out_path = sys.argv[3]
    if not (0 <= T < (1 << 30)):
        print("target out of domain", file=sys.stderr)
        return 2
    ks = [np.uint32(round_key(K, i)) for i in (1, 2, 3, 4)]
    target = np.uint32(T)

    found = None
    for base in range(0, SPACE, CHUNK):
        x = np.arange(base, base + CHUNK, dtype=np.uint32)
        L = x >> SHIFT15
        R = x & MASK15
        for k in ks:
            t = R + k
            t ^= t >> SHIFT9
            t = t * C1
            t ^= t >> SHIFT11
            f = t & MASK15
            L, R = R, L ^ f
        y = (L << SHIFT15) | R
        hits = np.nonzero(y == target)[0]
        if hits.size:
            found = int(x[hits[0]])
            break
    if found is None:
        print("no preimage found (target not in cipher range?)", file=sys.stderr)
        return 1
    with open(out_path, "w") as fh:
        json.dump({"x": found, "y": T}, fh)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x /app/crack.py

K=$(tr -d '[:space:]' < /app/key.txt)
T=$(tr -d '[:space:]' < /app/target.txt)
python3 /app/crack.py "$K" "$T" /app/secret.json

# self-check against the authoritative reference
python3 - "$K" "$T" <<'PY'
import json, sys
sys.path.insert(0, "/app")
from cipher import encrypt
K, T = int(sys.argv[1], 16), int(sys.argv[2], 16)
got = json.load(open("/app/secret.json"))
assert got["y"] == T
assert 0 <= got["x"] < (1 << 30)
assert encrypt(got["x"], K) == T, (got, encrypt(got["x"], K))
print("[self-check] preimage %08x verified against /app/cipher.py" % got["x"])
PY
echo "pearl-cipher oracle: done"
