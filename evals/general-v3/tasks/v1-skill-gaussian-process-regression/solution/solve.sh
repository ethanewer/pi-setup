#!/bin/bash
set -euo pipefail

cat > /app/gp.py <<'EOF'
import json
import numpy as np

xt = np.array(json.load(open('/app/xtrain.json')))
yt = np.array(json.load(open('/app/ytrain.json')))
xs = np.array(json.load(open('/app/xtest.json')))
l = 1.5
sigma2 = 0.1

def kern(a, b):
    d = a - b
    return np.exp(-(d*d)/(2*l*l))

K = kern(xt[:, None], xt[None, :])
Kinv = np.linalg.inv(K + sigma2*np.eye(len(xt)))
mean = []
for t in xs:
    kt = kern(t, xt)
    mean.append(float(kt @ Kinv @ yt))

with open('/app/gp_predictions.json','w') as f:
    json.dump([round(v,4) for v in mean], f)
EOF
python3 /app/gp.py