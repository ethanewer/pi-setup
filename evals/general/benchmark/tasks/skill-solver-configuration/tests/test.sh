#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
required=(
  "test_iter: 100"
  "test_interval: 500"
  "base_lr: 0.01"
  "max_iter: 20000"
  "lr_policy: \"step\""
  "gamma: 0.1"
  "stepsize: 8000"
  "momentum: 0.9"
  "weight_decay: 0.0005"
  "snapshot: 2000"
  "solver_mode: \"GPU\""
)
if [ -f "$APP/solver.prototxt" ]; then
  content=$(cat "$APP/solver.prototxt")
  ok=1
  for field in "${required[@]}"; do
    if ! printf '%s\n' "$content" | grep -Fq "$field"; then ok=0; fi
  done
  if [ "$ok" = "1" ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt