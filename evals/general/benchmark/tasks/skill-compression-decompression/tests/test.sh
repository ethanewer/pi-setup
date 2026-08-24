#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/plain.txt" ] && [ -f "$APP/payload.gz" ] && [ -f "$APP/recovered.txt" ]; then
  if python3 - "$APP" <<'PYEOF'
import gzip, sys
base = sys.argv[1]
original = open(base + '/plain.txt', 'rb').read()
recovered = open(base + '/recovered.txt', 'rb').read()
decompressed = gzip.decompress(open(base + '/payload.gz', 'rb').read())
ok = (recovered == original) and (decompressed == original)
sys.exit(0 if ok else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt