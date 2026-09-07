#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/circuit.json" ] && [ -f "$APP/assignments.json" ] && [ -f "$APP/outputs.json" ]; then
  if python3 - "$APP" <<'PY'
import json, sys
base = sys.argv[1]
circ = json.load(open(base + '/circuit.json'))
assigns = json.load(open(base + '/assignments.json'))

def gate(op, vals):
    if op == 'AND': return 1 if all(vals) else 0
    if op == 'OR':  return 1 if any(vals) else 0
    if op == 'XOR': return vals[0] ^ vals[1]
    if op == 'NOT': return 1 - vals[0]
    raise Exception(op)

expected = []
for asg in assigns:
    vals = {}
    for n in circ['nodes']:
        arr = [(vals[x] if x in vals else asg[x]) for x in n['in']]
        vals[n['id']] = gate(n['op'], arr)
    expected.append([vals[o] for o in circ['outputs']])
got = json.load(open(base + '/outputs.json'))
sys.exit(0 if got == expected else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt