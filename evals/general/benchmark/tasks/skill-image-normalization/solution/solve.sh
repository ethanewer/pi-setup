#!/bin/bash
set -euo pipefail
cat > /app/normalize.py <<'PYEOF'
import numpy as np
from PIL import Image
a = np.asarray(Image.open('/app/img_norm.png').convert('L'), dtype=float)
n = a / 255.0
m = float(n.mean())
open('/app/norm.txt', 'w').write(format(m, '.4f'))
PYEOF
python3 /app/normalize.py