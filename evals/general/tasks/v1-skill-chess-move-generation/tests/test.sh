#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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