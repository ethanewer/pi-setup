#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/mating.txt ]; then
  if python3 - <<'EOF'
import chess
fen=open('/app/position.txt').read().strip()
raw=open('/app/mating.txt').read().strip()
parts=raw.split()
if len(parts)!=1:
    raise SystemExit("must be exactly one move")
try:
    mv=chess.Move.from_uci(parts[0])
except Exception:
    raise SystemExit("not a valid UCI move")
b=chess.Board(fen)
if mv not in b.legal_moves:
    raise SystemExit("not legal in position")
bb=b.copy(); bb.push(mv)
if not bb.is_checkmate():
    raise SystemExit("not checkmate")
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt