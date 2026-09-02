#!/bin/bash
set -euo pipefail

cat > /app/attention.py <<'EOF'
import json
import math
import sys

sys.path.insert(0, "/app")
from attn_input import Q, K, V

def softmax(seq):
    ex = [math.exp(x) for x in seq]
    s = sum(ex)
    return [x / s for x in ex]

dk = len(K[0])
eye = math.sqrt(dk)

# scores[i][j] = dot(Q[i], K[j]) / sqrt(dk)
scores = []
for qi in Q:
    row = []
    for kj in K:
        row.append(sum(qi[m] * kj[m] for m in range(dk)) / eye)
    scores.append(row)

for i in range(len(scores)):
    scores[i] = softmax(scores[i])

# output[i] = sum_j scores[i][j] * V[j]
out = []
for i in range(len(Q)):
    row = [0.0, 0.0, 0.0]
    for j in range(len(V)):
        for m in range(len(row)):
            row[m] += scores[i][j] * V[j][m]
    out.append([round(x, 6) for x in row])

with open("/app/attention.json", "w") as f:
    json.dump(out, f)
EOF

python3 /app/attention.py