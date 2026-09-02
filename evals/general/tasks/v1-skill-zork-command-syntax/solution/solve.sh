#!/bin/bash
set -euo pipefail

cat > /app/zork_parser.py <<'EOF'
import json

MOVES = {
    "n": "north", "s": "south", "e": "east", "w": "west",
    "ne": "northeast", "nw": "northwest", "se": "southeast", "sw": "southwest",
}
ARTICLES = {"a", "an", "the"}

def normalize(line):
    toks = line.lower().strip().split()
    if toks and toks[0] == "go":
        toks = toks[1:]
    toks = [MOVES.get(t, t) for t in toks]
    toks = [t for t in toks if t not in ARTICLES]
    return toks

with open("/app/commands.txt") as f:
    lines = [ln.strip() for ln in f if ln.strip()]

out = [normalize(ln) for ln in lines]
with open("/app/zork_out.json", "w") as f:
    json.dump(out, f)
EOF

python3 /app/zork_parser.py