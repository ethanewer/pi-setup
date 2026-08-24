#!/bin/bash
set -euo pipefail
cat > /app/find_closest.py <<'PYEOF'
import json, math
data = json.load(open('/app/embed.json'))
sents = data['sentences']
vecs = data['embeddings']
def cosine(a, b):
    num = sum(x*y for x, y in zip(a, b))
    na = math.sqrt(sum(x*x for x in a))
    nb = math.sqrt(sum(x*x for x in b))
    if na == 0 or nb == 0:
        return 0.0
    return num / (na * nb)
res = []
for i in range(len(sents)):
    best = -1; bestj = -1
    for j in range(len(sents)):
        if i == j: continue
        s = cosine(vecs[i], vecs[j])
        if best == -1 or s > best or (abs(s - best) < 1e-12 and j < bestj):
            bestj = j; best = s
    res.append({'sentence': sents[i], 'closest': sents[bestj], 'score': round(best, 4)})
json.dump(res, open('/app/similarity.json', 'w'))
PYEOF
python3 /app/find_closest.py
