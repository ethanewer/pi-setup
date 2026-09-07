#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/tests/test_contract.py" ] && [ -f "$APP/tests/test_behavior.py" ] && [ -f "$APP/dispatcher.py" ]; then
  if python3 - "$APP/dispatcher.py" <<'PY'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("dispatcher", sys.argv[1])
if spec is None or spec.loader is None:
    sys.exit(1)
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception:
    sys.exit(1)
# Contract: LeasePool.hold() is the only touching mechanism and live starts at 0.
if not hasattr(mod, 'Dispatcher') or not hasattr(mod, 'LeasePool'):
    sys.exit(1)
sys.exit(0 if mod.LeasePool().live == 0 else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt