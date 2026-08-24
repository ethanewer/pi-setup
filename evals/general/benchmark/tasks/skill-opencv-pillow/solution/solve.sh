#!/bin/bash
# Oracle solution for skill-opencv-pillow.
set -euo pipefail

cat > /app/green_count.py <<'PYEOF'
import numpy as np
from PIL import Image

img = Image.open('/app/circle.png').convert('RGB')
arr = np.asarray(img)
mask = (arr[:, :, 1] > 200) & (arr[:, :, 0] < 50) & (arr[:, :, 2] < 50)
count = int(mask.sum())
with open('/app/green_count.txt', 'w') as f:
    f.write(str(count) + '\n')
PYEOF

python3 /app/green_count.py