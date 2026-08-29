#!/usr/bin/env bash
# iris-anchor oracle: does the real work (writes reusable programs, then RUNS
# them against the shipped fixtures to produce every deliverable).
set -euo pipefail

# 1) drop the reusable deliverable programs into /app
cp /solution/planner.py /solution/decode_board.py /app/
chmod +x /app/planner.py /app/decode_board.py

# 2) produce the path deliverable by running the planner on the visible grid
python3 /app/planner.py /app/grid.json -o /app/path.json

# 3) produce the board deliverable by decoding the camera image
python3 /app/decode_board.py /app/board.png -o /app/board.json

# 4) tune the MuJoCo model by measurement-only optimisation on the reference
cp /solution/tune.py /app/tune.py
python3 /app/tune.py
cp /tmp/tuned.xml /app/tuned.xml
rm -f /app/tune.py

echo "oracle done"