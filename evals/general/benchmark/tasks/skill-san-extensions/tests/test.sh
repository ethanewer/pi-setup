#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/san_result.json ]; then
  if python3 - <<'EOF'
import re, json

def classify(m):
    kind = "quiet"
    s = m
    if s.endswith('#'):
        kind = 'checkmate'; s = s[:-1]
    elif s.endswith('+'):
        kind = 'check'; s = s[:-1]
    if s in ('O-O', 'O-O-O'):
        return True, kind
    pawn = re.compile(r'^[a-h]?x?[a-h][1-8](?:=[QRBN])?$')
    piece = re.compile(r'^[KQRBN](?:x|[a-h1-8]x?)?[a-h][1-8]$')
    if pawn.fullmatch(s) or piece.fullmatch(s):
        return True, kind
    return False, None

moves = [l.strip() for l in open('/app/moves.txt') if l.strip()]
exp = []
for mv in moves:
    valid, kind = classify(mv)
    exp.append({"move": mv, "valid": valid, "kind": kind})

got = json.load(open('/app/san_result.json')).get('results')
if got != exp:
    raise SystemExit("mismatch")
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt