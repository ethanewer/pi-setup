#!/usr/bin/env bash
# Oracle: build the five board-engines deliverables in /app from the real
# implementations and smoke-run each one (the genuine work) before hand-off.
set -euo pipefail
mkdir -p /app
cp /solution/game.js      /app/game.js
cp /solution/chess.py     /app/chess.py
cp /solution/planner.py   /app/planner.py
cp /solution/mahjong.py   /app/mahjong.py
cp /solution/serialize.py /app/serialize.py
chmod +x /app/game.js /app/game.js /app/chess.py /app/planner.py /app/mahjong.py /app/serialize.py

# --- smoke-run each deliverable from /app with literal paths (real work) ---
node /app/game.js --selfcheck >/dev/null

python3 /app/chess.py legal "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" >/dev/null

printf '[["gather","chop","forge","market"],["quarry","quarry"],[]]\n' > /tmp/pl.json
python3 /app/planner.py /tmp/pl.json /tmp/pl_out.json

mkdir -p /tmp/hands
printf '["1m","9m","1p","9p","1s","9s","East","South","West","North","R","G","B","East"]' > /tmp/hands/orphans.json
python3 /app/mahjong.py /tmp/hands >/dev/null

printf '[[[0,7],[3,1]]]\n' > /tmp/ser.json
python3 /app/serialize.py /tmp/ser.json /tmp/ser_out.json

echo "oracle finished"