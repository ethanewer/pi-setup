#!/usr/bin/env bash
mkdir -p /logs/verifier

python3 - > /tmp/rv.txt 2>/dev/null <<'EOF'
import numpy as np, os, glob
ok = False
try:
    if os.path.isdir("/app/shards"):
        files = sorted(glob.glob("/app/shards/shard_*.npy"))
        if len(files) == 4 and [os.path.basename(f) for f in files] == [f"shard_{i}.npy" for i in range(4)]:
            original = np.load("/app/features.npy")
            shards = [np.load(f"/app/shards/shard_{i}.npy") for i in range(4)]
            if all(s.shape == (16, 8) and s.dtype == original.dtype for s in shards):
                if np.array_equal(np.concatenate(shards, axis=0), original):
                    ok = True
except Exception:
    ok = False
print(1 if ok else 0)
EOF

reward=$(cat /tmp/rv.txt 2>/dev/null | tr -dc '01' | sed 's/.*\([01]\)$/\1/')
if [ -z "$reward" ]; then reward=0; fi
echo "$reward" > /logs/verifier/reward.txt