#!/bin/bash
# Oracle: mean-pool the two sentences' word vectors and compute their cosine
# similarity, rounded to 4 decimals.
set -euo pipefail
python3 - <<'PYEOF'
import json, math

model = json.load(open('/app/embeddings.json'))
words = model['words']
dim = model['dim']

def mean_pool(tokens):
    vec = [0.0] * dim
    for t in tokens:
        v = words.get(t)
        if v is None:
            continue  # OOV token -> zero vector
        for i in range(dim):
            vec[i] += v[i]
    n = len(tokens)
    return [x / n for x in vec]

a = mean_pool(model['sentences']['A'])
b = mean_pool(model['sentences']['B'])
dot = sum(x * y for x, y in zip(a, b))
na = math.sqrt(sum(x * x for x in a))
nb = math.sqrt(sum(x * x for x in b))
cos = dot / (na * nb)

with open('/app/answer.txt', 'w') as out:
    out.write('cosine_similarity=%.4f\n' % cos)
print('cosine_similarity=%.4f' % cos)
PYEOF