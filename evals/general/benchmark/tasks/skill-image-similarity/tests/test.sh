#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import numpy as np
from PIL import Image
def vec(path):
    return np.asarray(Image.open(path).convert('L'), dtype=float).flatten()
a = vec('/app/img_a.png')
b = vec('/app/img_b.png')
cos = float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))
got = float(open('/app/cosine_similarity.txt').read().strip())
assert abs(got - cos) <= 1e-4, (got, cos)
assert cos >= -1.0 and cos <= 1.0
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt