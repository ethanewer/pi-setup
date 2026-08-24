#!/bin/bash
set -euo pipefail

cat > /app/formula_check.py <<'PYEOF'
import itertools

def F(p, q, r):
    # ( (p -> q) and (q -> r) ) -> (p -> r)
    imp = lambda a, b: (not a) or b
    return imp(imp(p, q) and imp(q, r), imp(p, r))

values = [True, False]
all_true = True
for p, q, r in itertools.product(values, repeat=3):
    if not F(p, q, r):
        all_true = False

with open('/app/verdict.txt', 'w') as f:
    f.write(('tautology' if all_true else 'nontheorem') + '\n')
PYEOF

python3 /app/formula_check.py
echo "wrote /app/verdict.txt"