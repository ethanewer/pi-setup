#!/bin/bash
set -euo pipefail
cat > /app/differential.py <<'PY'
sbox = [int(v, 16) for v in open('/app/sbox.txt').read().split()]
counts = [0] * 16
for x in range(16):
    d = sbox[x] ^ sbox[x ^ 1]
    counts[d] += 1
best_idx = min(i for i in range(16) if counts[i] == max(counts))
with open('/app/differential.txt', 'w') as f:
    for i in range(16):
        f.write(f"{i} {counts[i]}\n")
    f.write(f"best {max(counts)}\n")
PY
python3 /app/differential.py