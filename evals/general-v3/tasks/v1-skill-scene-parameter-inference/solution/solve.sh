#!/bin/bash
set -euo pipefail

cat > /app/infer.py <<'EOF'
import math, json

data = open('/app/render.ppm').read().split()
assert data[0] == 'P2'
W, H = int(data[1]), int(data[2])
vals = list(map(int, data[4:]))

pts = []
for y in range(H):
    for x in range(W):
        pts.append((x, y, vals[y * W + x]))

disc = [p for p in pts if p[2] > 20]
xs = [p[0] for p in disc]
ys = [p[1] for p in disc]
cx = round((min(xs) + max(xs)) / 2)
cy = round((min(ys) + max(ys)) / 2)
radius = round((max(xs) - min(xs)) / 2)

mv = max(p[2] for p in pts)
bx, by = next((x, y) for x, y, v in pts if v == mv)
az = math.degrees(math.atan2(by - cy, bx - cx)) % 360
az = round(az, 1)

with open('/app/scene_params.json', 'w') as f:
    json.dump({"cx": cx, "cy": cy, "radius": radius, "azimuth_deg": az}, f)
EOF

python3 /app/infer.py