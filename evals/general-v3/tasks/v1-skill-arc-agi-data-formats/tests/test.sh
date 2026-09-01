#!/bin/bash
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