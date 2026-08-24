#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ] && [ -f /app/tokens.txt ] && [ -f /app/merges.txt ]; then
  if python3 - <<'PYEOF'
import sys

def merge_all(tokens, a, b):
    out=[]
    i=0; n=len(tokens)
    while i<n:
        if i+1<n and tokens[i]==a and tokens[i+1]==b:
            out.append(a+b); i+=2
        else:
            out.append(tokens[i]); i+=1
    return out

tokens = open('/app/tokens.txt').read().split()
merges = [tuple(l.split()) for l in open('/app/merges.txt').read().splitlines() if l.split()]
for a,b in merges:
    while True:
        nxt = merge_all(tokens, a, b)
        if nxt == tokens: break
        tokens = nxt
expected = ' '.join(tokens)
got = open('/app/answer.txt').read().strip()
sys.exit(0 if got == expected else 1)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt