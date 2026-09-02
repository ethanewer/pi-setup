#!/bin/bash

mkdir -p /logs/verifier

reward=0

if [ -f /app/output.json ] && python3 - <<'PYEOF'
import chess, json, sys

FEN = "7k/2p2K2/p7/3n4/1b6/8/2PP4/R7 w - - 0 1"

with open("/app/output.json") as f:
    out = json.load(f)

def is_mate(b, m):
    b.push(m)
    mated = b.is_checkmate()
    b.pop()
    return mated

b = chess.Board(FEN)
expect_mates = sorted(m.uci() for m in b.legal_moves if is_mate(b, m))

claimed = open("/app/claim.txt").read().strip()

ok = True
if set(out.get("mating_moves", [])) != set(expect_mates):
    ok = False
if str(out.get("claimed_move", "")) != claimed:
    ok = False
if bool(out.get("claimed_is_mate")) != (claimed in expect_mates):
    ok = False

sys.exit(0 if ok else 1)
PYEOF
then
  reward=1
fi

echo "$reward" > /logs/verifier/reward.txt