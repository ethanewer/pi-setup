#!/bin/bash
# Oracle solution for skill-numpy-arrays.
set -euo pipefail

cat > /app/stats.py <<'PYEOF'
import json
import numpy as np

arr = np.loadtxt('/app/scores.txt', dtype=int)

count_gt15 = int((arr > 15).sum())
idx_div3 = np.where(arr % 3 == 0)[0].tolist()
mask10 = arr > 10
mean_gt10 = round(float(arr[mask10].mean()) if mask10.any() else 0.0, 2)
max_val = int(arr.max())

json.dump({'count_gt15': count_gt15,
           'idx_div3': idx_div3,
           'mean_gt10': mean_gt10,
           'max_val': max_val},
          open('/app/stats.json', 'w'))
PYEOF

python3 /app/stats.py