#!/bin/bash
mkdir -p /logs/verifier
reward=0

if python3 - <<'PY'
import sys
sbox = [int(v, 16) for v in open('/app/sbox.txt').read().split()]
counts = [0] * 16
for x in range(16):
    d = sbox[x] ^ sbox[x ^ 1]
    counts[d] += 1
best_idx = min(i for i in range(16) if counts[i] == max(counts))

lines = [l.strip() for l in open('/app/differential.txt').read().splitlines() if l.strip()]
assert len(lines) == 17, lines
for i in range(16):
    idx, cnt = lines[i].split()
    assert int(idx) == i and int(cnt) == counts[i], (i, lines[i], counts[i])
assert lines[16] == f"best {max(counts)}", lines[16]
PY
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt