#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/pty_out.txt" ]; then
  if python3 - "$APP/pty_out.txt" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
norm = data.replace(b'\r\n', b'\n')
expected = b'line one\nline two\nline three\n'
sys.exit(0 if norm == expected else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt