#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/zork_out.json ]; then
  if python3 - <<'PYEOF'
import json

MOVES = {
    "n": "north", "s": "south", "e": "east", "w": "west",
    "ne": "northeast", "nw": "northwest", "se": "southeast", "sw": "southwest",
}
ARTICLES = {"a", "an", "the"}

def normalize(line):
    toks = line.lower().split()
    if toks and toks[0] == "go":
        toks = toks[1:]
    toks = [MOVES.get(t, t) for t in toks]
    toks = [t for t in toks if t not in ARTICLES]
    return toks

with open("/app/commands.txt") as f:
    lines = [ln.strip() for ln in f if ln.strip()]
expected = [normalize(ln) for ln in lines]

with open("/app/zork_out.json") as f:
    got = json.load(f)

assert got == expected, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt