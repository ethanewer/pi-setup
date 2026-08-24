#!/bin/bash
set -euo pipefail

cat > /app/make_report.py <<'PY'
rows = []
for line in open('/app/input.txt', encoding='utf-8').read().splitlines():
    line = line.rstrip('\n')
    if not line.strip():
        continue
    name, score = line.split()
    rows.append((name, int(score)))
rows.sort(key=lambda r: r[0])
lines = [f"{n} {s}" for n, s in rows]
lines.append(f"TOTAL {sum(s for _, s in rows)}")
open('/app/report.txt', 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
print('\n'.join(lines))
PY

python3 /app/make_report.py