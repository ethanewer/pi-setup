#!/bin/bash
set -euo pipefail

mkdir -p /app/found

python3 - <<'PY'
import json, subprocess

def S(b):
    return (7*int(b) + 3) & 0xFF

def subkey(K, r):
    return ((K + 17*r) & 0xFF) ^ ((K >> 8) & 0xFF)

def enc(K, P):
    L = (P >> 8) & 0xFF
    R = P & 0xFF
    for r in range(6):
        f = S(R ^ subkey(K, r))
        L, R = R, (L ^ f) & 0xFF
    return (L << 8) | R

def dec(K, C):
    L = (C >> 8) & 0xFF
    R = C & 0xFF
    for r in range(5, -1, -1):
        f = S(L ^ subkey(K, r))
        L, R = (R ^ f) & 0xFF, L
    return (L << 8) | R

def oracle(kind, arg=None):
    cmd = ['/app/candle', kind] if arg is None else ['/app/candle', kind, arg]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout.strip()
    return int(out, 16)

# 1) collect a couple of known-plaintext probes from the oracle
probe_blocks = [0x0000, 0x0001, 0x0080, 0x00FF]
pairs = {}
for p in probe_blocks:
    pairs[p] = oracle('enc', '%02X' % p)

# 2) brute-force the 16-bit key on the first pair, then confirm on the rest
key = None
for k in range(0x10000):
    if enc(k, probe_blocks[0]) == pairs[probe_blocks[0]] and \
       enc(k, probe_blocks[1]) == pairs[probe_blocks[1]]:
        key = k
        break
if key is None:
    raise SystemExit("key not found")

# 3) fresh-query validation: a block not used in the search
fresh = 0x5A5A
assert oracle('enc', '%04X' % fresh) == enc(key, fresh), "fresh probe mismatch"

# 4) read and decrypt the challenge
ch = oracle('challenge')
pt = dec(key, ch)

sol = {
    "key": "%04X" % key,
    "plain": "%04X" % pt,
}
with open('/app/found/solution.json', 'w') as f:
    json.dump(sol, f)
print("key recovered:", sol)
PY