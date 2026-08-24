#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/input/image.npy" ] && [ -f "$APP/input/prompt.txt" ] && [ -f "$APP/model/mobilesam.npz" ] && [ -f "$APP/output/mask.npy" ] && [ -f "$APP/output/mask_count.txt" ]; then
  if python3 - "$APP" <<'PYEOF'
import sys
import numpy as np
base = sys.argv[1]
img = np.load(base + '/input/image.npy')
flat = img.reshape(32 * 32).astype(np.float32)
px, py = map(int, open(base + '/input/prompt.txt').read().strip().split())
feat = np.concatenate([flat, np.array([px/32.0, py/32.0], dtype=np.float32)])
d = np.load(base + '/model/mobilesam.npz')
hidden = np.tanh(feat @ d['W_img'] + d['b_img'])
logits = hidden @ d['W_mask'] + d['b_mask']
mask = (1.0/(1.0+np.exp(-logits))).reshape(32, 32).astype(np.float32)
expected_count = int(np.count_nonzero(mask > 0.5))
got_mask = np.load(base + '/output/mask.npy')
got_count_txt = open(base + '/output/mask_count.txt').read().strip()
ok = (got_mask.shape == (32, 32)) and (got_count_txt == str(expected_count))
sys.exit(0 if ok else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt