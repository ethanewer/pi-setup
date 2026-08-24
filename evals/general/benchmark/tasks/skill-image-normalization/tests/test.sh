#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import numpy as np
from PIL import Image
a = np.asarray(Image.open('/app/img_norm.png').convert('L'), dtype=float)
m = float((a / 255.0).mean())
got = float(open('/app/normalization.txt').read().strip())
assert abs(got - m) <= 1e-4, (got, m)
assert 0.0 <= got <= 1.0
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt