#!/usr/bin/env bash
# Oracle: partition tensor into 4 equal contiguous shards along axis 0.
python3 - <<'EOF'
import numpy as np, os
t = np.load("/app/features.npy")
os.makedirs("/app/shards", exist_ok=True)
n = 4
k = t.shape[0] // n
for i in range(n):
    np.save(f"/app/shards/shard_{i}.npy", t[i*k:(i+1)*k])
print("done")
EOF