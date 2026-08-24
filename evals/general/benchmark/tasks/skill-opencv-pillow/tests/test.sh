#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/green_count.txt ]; then
  if python3 - <<'PYEOF'
import numpy as np
from PIL import Image
img = Image.open('/app/circle.png').convert('RGB')
arr = np.asarray(img)
mask = (arr[:, :, 1] > 200) & (arr[:, :, 0] < 50) & (arr[:, :, 2] < 50)
expect = int(mask.sum())
got = int(open('/app/green_count.txt').read().strip())
assert got == expect, (got, expect)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt