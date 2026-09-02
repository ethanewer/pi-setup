#!/bin/bash
set -euo pipefail

cat > /app/run.py <<'EOF'
import numpy as np

x = np.load('/app/data/x.npy')
d = np.load('/app/data/net.npz')

hidden = np.tanh(x @ d['W1'] + d['b1'])
logits = hidden @ d['W2'] + d['b2']
cls = int(np.argmax(logits, axis=1)[0])

with open('/app/class.txt', 'w') as f:
    f.write(str(cls))
EOF

python3 /app/run.py