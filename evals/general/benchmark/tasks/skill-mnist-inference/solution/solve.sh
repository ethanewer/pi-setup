#!/bin/bash
set -euo pipefail

cat > /app/predict.py <<'EOF'
import numpy as np

x = np.load('/app/data/x.npy')
d = np.load('/app/data/model.npz')
W1, b1, W2, b2 = d['W1'], d['b1'], d['W2'], d['b2']

z1 = x @ W1 + b1
h = 1.0 / (1.0 + np.exp(-z1))
logits = h @ W2 + b2
digit = int(np.argmax(logits, axis=1)[0])

with open('/app/prediction.txt', 'w') as f:
    f.write(str(digit))
EOF

python3 /app/predict.py