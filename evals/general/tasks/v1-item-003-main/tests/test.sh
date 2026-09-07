#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/sanitize.py" ] && [ -f "$APP/tests/test_sanitizer.py" ] && [ -f "$APP/status.txt" ]; then
  status=$(cat "$APP/status.txt")
  if [ "$status" = "PASS" ]; then
    if python3 - "$APP/sanitize.py" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sanitize", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception:
    sys.exit(1)
sys.exit(0 if callable(getattr(mod, 'sanitize_html', None)) else 1)
PYEOF
    then reward=1
    fi
  fi
fi
echo "$reward" > /logs/verifier/reward.txt