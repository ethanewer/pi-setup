#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json
ranks = {}
for i, line in enumerate(open('/app/merges.txt')):
    line = line.strip()
    if not line:
        continue
    t1, t2, new = line.split()
    ranks[(t1, t2)] = (i, new)
tokens = list(open('/app/text_src.txt').read())
while True:
    present = set()
    for i in range(len(tokens) - 1):
        present.add((tokens[i], tokens[i + 1]))
    cand = [(rank, pair, new) for pair, (rank, new) in ranks.items() if pair in present]
    if not cand:
        break
    cand.sort(key=lambda x: x[0])
    _, pair, new = cand[0]
    t1, t2 = pair
    out = []
    i = 0
    while i < len(tokens):
        if i + 1 < len(tokens) and tokens[i] == t1 and tokens[i + 1] == t2:
            out.append(new)
            i += 2
        else:
            out.append(tokens[i])
            i += 1
    tokens = out

got = json.load(open('/app/tokens.json'))
assert got['tokens'] == tokens, (got['tokens'], tokens)
assert got['count'] == len(tokens), (got['count'], len(tokens))
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt