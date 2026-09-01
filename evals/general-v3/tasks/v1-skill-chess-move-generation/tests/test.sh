#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json, chess
pos = json.load(open('/app/positions.json'))
got = json.load(open('/app/moves.json'))
assert isinstance(got, dict)
for it in pos:
    b = chess.Board(it['fen'])
    moves = sorted(m.uci() for m in b.legal_moves)
    assert got.get(it['id']) == moves, (it['id'], got.get(it['id']), moves)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt