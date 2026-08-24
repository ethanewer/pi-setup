#!/bin/bash
set -euo pipefail

cat > /app/reassemble.py <<'EOF'
with open('/app/fragments.txt') as f:
    frags = [line.rstrip('\n') for line in f if line.strip()]

current = frags[0]
frags = frags[1:]

while frags:
    best_overlap = -1
    best_idx = -1
    for i, fr in enumerate(frags):
        m = min(len(current), len(fr))
        ov = 0
        for k in range(m, 0, -1):
            if current[-k:] == fr[:k]:
                ov = k
                break
        if ov > best_overlap:
            best_overlap = ov
            best_idx = i
    current = current + frags[best_idx][best_overlap:]
    frags.pop(best_idx)

with open('/app/original.txt', 'w') as f:
    f.write(current)
EOF
python3 /app/reassemble.py