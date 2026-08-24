#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/red_count.txt ]; then
  if python3 - <<'PYEOF'
import sys
import cv2

img = cv2.imread('/app/shapes.png')
mask = cv2.inRange(img, (0, 0, 200), (100, 100, 255))
expected = int(cv2.countNonZero(mask))
got = open('/app/red_count.txt').read().strip()
ok = (expected == 3600 and got == str(expected))
sys.exit(0 if ok else 1)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
