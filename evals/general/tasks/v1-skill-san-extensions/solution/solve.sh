#!/bin/bash
set -euo pipefail

cat > /app/validate_san.py <<'EOF'
import re, json

def classify(m):
    kind = "quiet"
    s = m
    if s.endswith('#'):
        kind = 'checkmate'
        s = s[:-1]
    elif s.endswith('+'):
        kind = 'check'
        s = s[:-1]
    if s in ('O-O', 'O-O-O'):
        return True, kind
    pawn = re.compile(r'^[a-h]?x?[a-h][1-8](?:=[QRBN])?$')
    piece = re.compile(r'^[KQRBN](?:x|[a-h1-8]x?)?[a-h][1-8]$')
    if pawn.fullmatch(s) or piece.fullmatch(s):
        return True, kind
    return False, None

moves = [l.strip() for l in open('/app/moves.txt') if l.strip()]
results = []
for mv in moves:
    valid, kind = classify(mv)
    results.append({"move": mv, "valid": valid, "kind": kind})

with open('/app/san_result.json', 'w') as f:
    json.dump({"results": results}, f)
EOF

python3 /app/validate_san.py