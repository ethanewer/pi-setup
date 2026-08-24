#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/xs.json" ] && [ -f "$APP/diffs.json" ]; then
  if python3 - "$APP" <<'PY'
import json, sys
base = sys.argv[1]
xs = json.load(open(base + '/xs.json'))
h = 0.01
def f(x):
    return x**3 - 2.0*x + 1.0
exp = [round((f(x+h) - f(x-h)) / (2*h), 3) for x in xs[1:-1]]
got = json.load(open(base + '/diffs.json'))
if not isinstance(got, list) or len(got) != len(exp):
    sys.exit(1)
sys.exit(0 if all(abs(a-b) < 1e-9 for a, b in zip(got, exp)) else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt