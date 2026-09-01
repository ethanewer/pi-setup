#!/usr/bin/env bash
# Oracle: create every deliverable by doing the real work under /app.
set -euo pipefail

cp /solution/solve_mip.py    /app/solve_mip.py
cp /solution/corners.py      /app/corners.py
cp /solution/quartic_min.py  /app/quartic_min.py
cp /solution/sinkhorn.py     /app/sinkhorn.py
chmod +x /app/*.py

cd /app
python3 /app/solve_mip.py    /app/model.mps            /app/mip_result.json
python3 /app/corners.py      /app/instance_corners.json /app/corners.txt
python3 /app/quartic_min.py  /app/instance_quartic.json /app/quartic_solution.json
python3 /app/sinkhorn.py     /app/instance_sinkhorn.json /app/ot_cost.json

echo "oracle complete"