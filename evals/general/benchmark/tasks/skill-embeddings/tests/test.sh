#!/bin/bash
# Verifier: recompute the mean-pooled embeddings and cosine similarity from
# /app/embeddings.json and compare with /app/answer.txt (tolerance 0.0005).
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ]; then
  if python3 - <<'PYEOF'
import json
import math

model = json.load(open('/app/embeddings.json'))
words = model['words']
dim = model['dim']

def mean_pool(tokens):
    vec = [0.0] * dim
    for t in tokens:
        v = words.get(t)
        if v is None:
            continue
        for i in range(dim):
            vec[i] += v[i]
    return [x / len(tokens) for x in vec]

a = mean_pool(model['sentences']['A'])
b = mean_pool(model['sentences']['B'])
dot = sum(x * y for x, y in zip(a, b))
na = math.sqrt(sum(x * x for x in a))
nb = math.sqrt(sum(x * x for x in b))
expected = round(dot / (na * nb), 4)

line = open('/app/answer.txt').read().strip()
assert line.startswith('cosine_similarity=')
got = float(line.split('=', 1)[1])
assert abs(got - expected) <= 0.0005, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt