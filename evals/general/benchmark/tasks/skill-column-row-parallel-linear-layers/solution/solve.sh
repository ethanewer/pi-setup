#!/bin/bash
set -euo pipefail

cat > /app/split.py <<'EOF'
import json

data = json.load(open("/app/layers.json"))
out = {}
for L in data["layers"]:
    w = L["weights"]
    tiles = L["num_tiles"]
    t = L["tile_id"]
    if L["kind"] == "column-parallel":
        out_feat = L["out_features"]
        per = out_feat // tiles
        lo, hi = t*per, (t+1)*per
        shard = [row[lo:hi] for row in w]
    else:  # row-parallel
        in_feat = L["in_features"]
        per = in_feat // tiles
        lo, hi = t*per, (t+1)*per
        shard = w[lo:hi]
    out[L["name"]] = {"shard": shard}
json.dump(out, open("/app/shard.json", "w"))
EOF

python3 /app/split.py