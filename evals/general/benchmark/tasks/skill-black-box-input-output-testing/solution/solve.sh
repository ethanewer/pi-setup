#!/bin/bash
set -euo pipefail
cat > /app/model.py <<'PYEOF'
def model(n):
    return n * n + 1
PYEOF
python3 - <<'PYEOF'
import sys
sys.path.insert(0, '/app')
from model import model
with open('/app/test_inputs.txt') as f:
    ins = [int(x) for x in f.read().split()]
with open('/app/predictions.txt', 'w') as f:
    for n in ins:
        f.write(str(model(n)) + chr(10))
PYEOF
