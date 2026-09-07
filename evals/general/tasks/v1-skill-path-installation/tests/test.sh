#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
# Implementation must be installed to a custom path and importable from there.
if [ -f /app/vendor/mytool/greet.py ] && [ -f /app/use.py ] && [ -f /app/out.txt ]; then
python3 - <<'PYEOF'
import sys
sys.path.insert(0, '/app/vendor')
try:
    import mytool.greet as g
    ok = g.hello('world') == 'Hello, world'
    sys.exit(0 if ok else 1)
except Exception:
    sys.exit(1)
PYEOF
  rc1=$?
  content_ok=0
  if python3 /app/use.py 2>/dev/null && [ -f /app/out.txt ]; then
    content=$(sed -e 's/[[:space:]]*$//' /app/out.txt)
    if [ "$content" = "Hello, world" ]; then content_ok=1; fi
  fi
  if [ $rc1 -eq 0 ] && [ $content_ok -eq 1 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt