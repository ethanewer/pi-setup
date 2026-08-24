#!/bin/bash
set -euo pipefail
python3 - <<'PYEOF'
import numpy as np
data = np.genfromtxt('/app/regression.csv', delimiter=',', skip_header=1)
X = data[:, :5]
y = data[:, 5]
coefs, *_ = np.linalg.lstsq(X, y, rcond=None)
open('/app/coeffs.txt', 'w').write(' '.join(f'{c:.10f}' for c in coefs) + '\n')
PYEOF