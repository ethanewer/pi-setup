#!/bin/bash
# Oracle solution for skill-opencv.
set -euo pipefail

cat > /app/red_count.py <<'PYEOF'
import cv2

img = cv2.imread('/app/shapes.png')
mask = cv2.inRange(img, (0, 0, 200), (100, 100, 255))
count = int(cv2.countNonZero(mask))
with open('/app/red_count.txt', 'w') as f:
    f.write(str(count) + '\n')
PYEOF

python3 /app/red_count.py