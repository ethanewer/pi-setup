#!/bin/bash
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