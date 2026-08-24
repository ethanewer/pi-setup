#!/bin/bash
set -euo pipefail

cat > /app/report.py <<'PYEOF'
from dataclasses import dataclass

@dataclass
class Record:
    name: str
    value: int

records = []
with open('/app/records.txt') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        name, value = line.split()
        records.append(Record(name=name, value=int(value)))

mean = sum(r.value for r in records) / len(records)

with open('/app/report.txt', 'w') as f:
    for r in records:
        f.write(f'{r.name}={r.value}\n')
    f.write(f'mean={mean:.2f}\n')
PYEOF

python3 /app/report.py
echo "wrote /app/report.txt"