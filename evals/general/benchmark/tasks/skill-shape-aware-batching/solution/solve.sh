#!/bin/bash
set -euo pipefail

mkdir -p /app/out

python3 - <<'PY'
import json

items = json.load(open('/app/items.json'))
CAP = 32
# simple first-fit greedy (sorted descending) yields an optimal packing here
order = sorted(items, key=lambda it: -it['size'])
bins = []          # list of (used, [names])
for it in order:
    placed = False
    for b in bins:
        if b[0] + it['size'] <= CAP:
            b[0] += it['size']
            b[1].append(it['name'])
            placed = True
            break
    if not placed:
        bins.append([it['size'], [it['name']]])

out = [b[1] for b in bins]
with open('/app/out/batches.json', 'w') as f:
    json.dump(out, f)
print("batches:", len(out))
PY