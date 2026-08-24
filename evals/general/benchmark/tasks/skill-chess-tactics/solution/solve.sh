#!/bin/bash
set -euo pipefail

cat > /app/tactic.py <<'EOF'
import chess

fen = open("/app/position.txt").read().strip()
b = chess.Board(fen)
for m in b.legal_moves:
    bb = b.copy()
    bb.push(m)
    if bb.is_checkmate():
        open("/app/mating.txt", "w").write(m.uci())
        break
EOF

python3 /app/tactic.py