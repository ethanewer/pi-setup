#!/bin/bash

# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier

reward=0

if [ -f /app/out/error.json ]; then
python3 - <<'PY'
import json, re, sys

lines = open('/app/run.log', encoding='utf-8', errors='replace').read().splitlines()
exp_line = None
exp_msg = None
for i, ln in enumerate(lines):
    if ln.startswith('!'):
        exp_msg = ln[1:].strip().rstrip('.')
        for j in range(i + 1, len(lines)):
            m = re.match(r'^l\.(\d+)', lines[j])
            if m:
                exp_line = int(m.group(1))
                break
        break
if exp_line is None:
    sys.exit(1)

try:
    d = json.load(open('/app/out/error.json'))
except Exception:
    sys.exit(1)

if d.get('line') != exp_line:
    sys.exit(1)
if str(d.get('message')).strip().rstrip('.') != exp_msg:
    sys.exit(1)

sys.exit(0)
PY
  if [ $? -eq 0 ]; then reward=1; else reward=0; fi
fi

echo "$reward" > /logs/verifier/reward.txt