#!/bin/bash
set -euo pipefail
cat > /app/similarity.py <<'PYEOF'
import numpy as np
from PIL import Image
def vec(path):
    return np.asarray(Image.open(path).convert('L'), dtype=float).flatten()
a = vec('/app/img_a.png')
b = vec('/app/img_b.png')
cos = float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))
open('/app/cosine_similarity.txt', 'w').write(format(cos, '.4f'))
PYEOF
python3 /app/similarity.py