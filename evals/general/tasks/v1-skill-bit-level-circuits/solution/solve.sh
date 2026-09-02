#!/bin/bash
set -euo pipefail
cat > /app/eval_circuit.py <<'PYEOF'
import json
circ = json.load(open('/app/circuit.json'))
assigns = json.load(open('/app/assignments.json'))
def eval_node_gate(op, vals):
    if op == 'AND': return 1 if all(vals) else 0
    if op == 'OR': return 1 if any(vals) else 0
    if op == 'XOR': return vals[0] ^ vals[1]
    if op == 'NOT': return 1 - vals[0]
    raise ValueError(op)
results = []
for asg in assigns:
    vals = {}
    for n in circ['nodes']:
        a = [(vals[x] if x in vals else asg[x]) for x in n['in']]
        vals[n['id']] = eval_node_gate(n['op'], a)
    results.append([vals[oid] for oid in circ['outputs']])
json.dump(results, open('/app/outputs.json', 'w'))
PYEOF
python3 /app/eval_circuit.py
