#!/bin/bash
# Oracle solution for skill-open-english-wordnet-schema.
set -euo pipefail

cat > /app/wordnet_probe.py <<'PYEOF'
import json

data = json.load(open('/app/wordnet_subset.json'))
synsets = {s['synsetId']: s for s in data['synsets']}

# Find the canine sense of "dog": lemma "dog" + definition containing "Canis".
start = None
for s in synsets.values():
    if 'dog' in s['lemmas'] and 'Canis' in s['definition']:
        start = s['synsetId']
assert start is not None

out = []
cur = synsets[start]
while cur['hypernyms']:
    nxt = synsets[cur['hypernyms'][0]]
    if not nxt['hypernyms']:
        break   # next is the root synset (entity) -- exclude it
    cur = nxt
    out.append(cur['lemmas'][0])

with open('/app/chain.txt', 'w') as f:
    f.write('\n'.join(out) + '\n')
PYEOF

python3 /app/wordnet_probe.py