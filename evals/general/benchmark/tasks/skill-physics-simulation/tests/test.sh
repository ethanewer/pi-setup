#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.txt ]; then
python3 - <<'PYEOF'
import sys
try:
    x = 0.0; y = 0.0; vx = 50.0; vy = 60.0
    g = 9.81; k = 0.05; dt = 0.1
    while True:
        vx = vx + (-k * vx) * dt
        vy = vy + (-g - k * vy) * dt
        x = x + vx * dt
        y = y + vy * dt
        if y < 0.0:
            break
    expected = round(x, 3)
    got_raw = open('/app/result.txt').read().strip()
    got = round(float(got_raw), 3)
    sys.exit(0 if abs(got - expected) < 1e-6 else 1)
except Exception:
    sys.exit(1)
PYEOF
  if [ $? -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt