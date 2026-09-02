#!/bin/bash
# Verifier for skill-serial-console: recompute expected facts from uart.log.
mkdir -p /logs/verifier
reward=0

if [ -f /app/uart.log ] && [ -f /app/answer.json ]; then
  if python3 - <<'PYEOF'
import json, re, sys

log_path = '/app/uart.log'
frames = []
with open(log_path) as fh:
    for line in fh:
        line = line.strip()
        m = re.match(r'^RX ([0-9a-fA-F]{2})$', line)
        if m:
            frames.append(int(m.group(1), 16))

expected = {
    'num_frames': len(frames),
    'max_byte': max(frames) if frames else 0,
    'last_byte': frames[-1] if frames else 0,
}

try:
    got = json.load(open('/app/answer.json'))
except Exception:
    sys.exit(1)

if not isinstance(got, dict):
    sys.exit(1)
if {k: got.get(k) for k in expected} != expected:
    sys.exit(1)
print('serial console probe verified')
PYEOF
  then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt