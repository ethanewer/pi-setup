#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/lexer_rules.json ] && [ -f /app/input.txt ] && [ -f /app/token_sequence.json ]; then
  if python3 - <<'EOF'
import json, re, sys
rules = json.load(open('/app/lexer_rules.json'))['rules']
src = open('/app/input.txt').read().strip()
names = []
pos = 0
while pos < len(src):
    best = None
    for r in rules:
        m = re.compile(r['pattern']).match(src, pos)
        if m and (best is None or m.end() - pos > best[1]):
            best = (r['name'], m.end() - pos)
    if best is None:
        sys.exit('lex error')
    names.append(best[0])
    pos += best[1]
got = json.load(open('/app/token_sequence.json'))
if got != names:
    sys.exit('mismatch')
sys.exit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt