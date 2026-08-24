#!/bin/bash
set -euo pipefail
# Reference BPE merge application; deterministic for the fixed inputs.
python3 - <<'PYEOF'
def merge_all(tokens, a, b):
    out = []
    i = 0
    n = len(tokens)
    while i < n:
        if i + 1 < n and tokens[i] == a and tokens[i + 1] == b:
            out.append(a + b)
            i += 2
        else:
            out.append(tokens[i])
            i += 1
    return out

tokens = open('/app/tokens.txt').read().split()
merges = [tuple(line.split()) for line in open('/app/merges.txt').read().splitlines() if line.split()]
for a, b in merges:
    while True:
        nxt = merge_all(tokens, a, b)
        if nxt == tokens:
            break
        tokens = nxt
open('/app/answer.txt', 'w').write(' '.join(tokens) + '\n')
PYEOF