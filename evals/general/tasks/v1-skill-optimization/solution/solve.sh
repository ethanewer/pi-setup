#!/bin/bash
# Oracle solution for skill-optimization.
set -euo pipefail

cat > /app/optimizer.py <<'PYEOF'
import json
import sys
sys.path.insert(0, '/app')
from objective import objective

import numpy as np
from scipy.optimize import minimize

res = minimize(objective, np.array([0.0, 0.0]), method='BFGS')
x = [float(res.x[0]), float(res.x[1])]
f = float(res.fun)
json.dump({'x': x, 'f': f}, open('/app/solution.json', 'w'))
PYEOF

python3 /app/optimizer.py