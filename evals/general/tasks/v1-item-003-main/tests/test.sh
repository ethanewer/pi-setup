#!/bin/bash
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