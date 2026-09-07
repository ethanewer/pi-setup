#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/app.py" ]; then
  if python3 - "$APP" <<'PYEOF'
import importlib.util, sys
base = sys.argv[1]
spec = importlib.util.spec_from_file_location("app", base + '/app.py')
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except Exception:
    sys.exit(1)
if not hasattr(mod, 'app'):
    sys.exit(1)
app = mod.app
try:
    c = app.test_client()
    r1 = c.get('/')
    r2 = c.get('/api/greet?name=Ada')
except Exception:
    sys.exit(1)
ok = r1.status_code == 200 and r1.get_json() == {"status": "ok"}
ok = ok and r2.status_code == 200 and r2.get_json() == {"message": "Hello, Ada!"}
sys.exit(0 if ok else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt