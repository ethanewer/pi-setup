#!/bin/bash
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