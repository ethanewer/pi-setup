#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
import json
layers = json.load(open('/app/layers.json'))['layers']
depths = [float(x) for x in open('/app/depths.csv').read().strip().split(',')]
mapping = {}
for d in depths:
    for L in layers:
        if L['min'] <= d < L['max']:
            mapping[str(int(d))] = L['name']
            break
with open('/app/assignments.json','w') as f:
    json.dump(mapping, f)
print(mapping)
EOF