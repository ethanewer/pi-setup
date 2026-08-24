#!/bin/bash
set -euo pipefail

cat > /app/analyze.py <<'PYEOF'
with open('/app/image.pgm') as f:
    lines = [ln for ln in f.read().splitlines() if ln.strip()]
assert lines[0] == 'P2', lines[0]
w, h = map(int, lines[1].split())
# line[2] is the max value; pixel values follow from line[3] onward
values = [int(t) for t in ' '.join(lines[3:]).split()]
assert len(values) == w * h

bright = sum(1 for v in values if v >= 128)
mean = sum(values) / len(values)

with open('/app/report.txt', 'w') as f:
    f.write(f"width={w}\n")
    f.write(f"height={h}\n")
    f.write(f"bright={bright}\n")
    f.write(f"mean={mean:.2f}\n")
PYEOF

python3 /app/analyze.py