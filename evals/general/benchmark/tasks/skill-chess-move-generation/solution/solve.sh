#!/bin/bash
set -euo pipefail

cat > /app/gener.py <<'EOF'
import json, chess

pos = json.load(open("/app/positions.json"))
out = {}
for it in pos:
    b = chess.Board(it["fen"])
    moves = sorted(m.uci() for m in b.legal_moves)
    out[it["id"]] = moves
json.dump(out, open("/app/moves.json", "w"))
EOF

python3 /app/gener.py