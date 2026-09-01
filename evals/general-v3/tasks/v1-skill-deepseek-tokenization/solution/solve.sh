#!/bin/bash
set -euo pipefail
cat > /app/tokenizer.py <<'PY'
import json

ranks = {}
with open('/app/merges.txt') as f:
    for i, line in enumerate(f):
        line = line.strip()
        if not line:
            continue
        t1, t2, new = line.split()
        ranks[(t1, t2)] = (i, new)   # (rank, new-token)

tokens = list(open('/app/text_src.txt').read())
while True:
    present = set()
    for i in range(len(tokens) - 1):
        present.add((tokens[i], tokens[i + 1]))
    candidates = [(rank, pair, new) for pair, (rank, new) in ranks.items() if pair in present]
    if not candidates:
        break
    candidates.sort(key=lambda x: x[0])
    _, pair, new = candidates[0]
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

with open('/app/tokens.json', 'w') as f:
    json.dump({"tokens": tokens, "count": len(tokens)}, f)
PY
python3 /app/tokenizer.py
