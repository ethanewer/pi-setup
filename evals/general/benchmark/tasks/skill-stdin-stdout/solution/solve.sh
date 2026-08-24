#!/bin/bash
set -euo pipefail

cat > /app/transform.py <<'PY'
import sys

rows = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    name, score = line.rsplit(':', 1)
    rows.append((name.upper(), int(score)))

# stable sort by score descending keeps original order among ties
rows.sort(key=lambda r: r[1], reverse=True)
for name, score in rows:
    print(f"{name} {score}")
PY