#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.txt ]; then
  if python3 - <<'PYEOF'
from collections import defaultdict
inv = defaultdict(set)
for line in open('/app/documents.txt'):
    line = line.strip()
    if not line:
        continue
    docid, text = line.split('|', 1)
    for word in text.split():
        inv[word].add(docid)
query = ['the', 'quick']
expected = ','.join(sorted(set.intersection(*(inv[q] for q in query))))
got = open('/app/result.txt').read().strip()
assert got == expected, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt