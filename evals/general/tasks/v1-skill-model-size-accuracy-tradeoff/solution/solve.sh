#!/bin/bash
set -euo pipefail

cat > /app/analyze.py <<'EOF'
import csv, json

rows = []
with open('/app/models.csv') as f:
    for r in csv.DictReader(f):
        rows.append({'model': r['model'], 'acc': float(r['accuracy_pct'])})

# confirm increasing order
params = []
with open('/app/models.csv') as f:
    for r in csv.DictReader(f):
        params.append(float(r['params_m']))
assert all(params[i] < params[i+1] for i in range(len(params)-1)), "not sorted"

small_to_large_delta = round(rows[-1]['acc'] - rows[0]['acc'], 2)

best = max(rows, key=lambda r: r['acc'])
best_model, best_acc = best['model'], best['acc']

max_gain = None
max_row = None
for i in range(len(rows) - 1):
    gain = round(rows[i+1]['acc'] - rows[i]['acc'], 2)
    if max_gain is None or gain > max_gain:
        max_gain = gain
        max_row = f"{rows[i]['model']}->{rows[i+1]['model']}"

result = {
    "best_model": best_model,
    "best_acc": best_acc,
    "max_gain_row": max_row,
    "max_gain_value": max_gain,
    "small_to_large_delta": small_to_large_delta,
}
with open('/app/analysis.json', 'w') as f:
    json.dump(result, f)
EOF

python3 /app/analyze.py