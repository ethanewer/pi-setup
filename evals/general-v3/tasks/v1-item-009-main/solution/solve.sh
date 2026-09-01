#!/bin/bash
set -euo pipefail

cat > /app/write_solution.py <<'PYEOF'
import chess, json

FEN = "7k/2p2K2/p7/3n4/1b6/8/2PP4/R7 w - - 0 1"

def is_mate(b, move):
    b.push(move)
    mated = b.is_checkmate()
    b.pop()
    return mated

b = chess.Board(FEN)
mates = sorted(m.uci() for m in b.legal_moves if is_mate(b, m))
claimed = open("/app/claim.txt").read().strip()

out = {
    "mating_moves": mates,
    "claimed_move": claimed,
    "claimed_is_mate": claimed in mates,
}
with open("/app/output.json", "w") as f:
    json.dump(out, f)
PYEOF

python3 /app/write_solution.py