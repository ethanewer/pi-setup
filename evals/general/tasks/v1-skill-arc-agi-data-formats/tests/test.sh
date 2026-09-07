#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/arc_task.json" ] && [ -f "$APP/answer.json" ]; then
  if python3 - "$APP" <<'PYEOF'
import json, sys
base = sys.argv[1]
task = json.load(open(base + '/arc_task.json'))
first = task['train'][0]['input']
exp = {
    "first_train_input_rows": len(first),
    "first_train_input_cols": len(first[0]) if first else 0,
    "first_train_input_colors": sorted(set(c for row in first for c in row)),
    "num_train_examples": len(task['train']),
    "num_test_examples": len(task['test']),
}
got = json.load(open(base + '/answer.json'))
sys.exit(0 if got == exp else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt