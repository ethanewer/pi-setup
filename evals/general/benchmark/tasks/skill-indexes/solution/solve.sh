#!/bin/bash
set -euo pipefail
cat > /app/index.py <<'PYEOF'
from collections import defaultdict
inv = defaultdict(set)
terms = {}
for line in open('/app/documents.txt'):
    line = line.strip()
    if not line:
        continue
    docid, text = line.split('|', 1)
    for word in text.split():
        inv[word].add(docid)
query = ['the', 'quick']
result = sorted(set.intersection(*(inv[q] for q in query)))
open('/app/answer.txt', 'w').write(','.join(result))
PYEOF
python3 /app/index.py