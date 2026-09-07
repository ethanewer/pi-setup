#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/out.txt ]; then
  got=$(sed -e 's/[[:space:]]*$//' /app/out.txt)
  import_ok=0
  python3 - <<'PYEOF'
import sys
try:
    import myprobe
    sys.exit(0 if myprobe.probe() == 'probe ok' else 1)
except Exception:
    sys.exit(1)
PYEOF
  if [ $? -eq 0 ]; then import_ok=1; fi
  if [ "$got" = "probe ok" ] && [ $import_ok -eq 1 ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt