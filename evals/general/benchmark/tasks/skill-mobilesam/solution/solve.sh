#!/bin/bash
set -euo pipefail

cat > /app/segment.py <<'EOF'
import numpy as np

img = np.load('/app/input/image.npy')            # (1,1,32,32)
flat = img.reshape(32 * 32).astype(np.float32)   # (1024,)

with open('/app/input/prompt.txt') as f:
    px, py = map(int, f.read().strip().split())
prompt = np.array([px / 32.0, py / 32.0], dtype=np.float32)

feat = np.concatenate([flat, prompt])            # (1026,)

d = np.load('/app/model/mobilesam.npz')
W_img, b_img = d['W_img'], d['b_img']
W_mask, b_mask = d['W_mask'], d['b_mask']

hidden = np.tanh(feat @ W_img + b_img)
logits = hidden @ W_mask + b_mask                # (1024,)
mask = (1.0 / (1.0 + np.exp(-logits))).reshape(32, 32).astype(np.float32)

import os
os.makedirs('/app/output', exist_ok=True)
np.save('/app/output/mask.npy', mask)
count = int(np.count_nonzero(mask > 0.5))
with open('/app/output/mask_count.txt', 'w') as f:
    f.write(str(count))
EOF

python3 /app/segment.py