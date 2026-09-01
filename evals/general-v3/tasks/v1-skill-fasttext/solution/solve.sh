#!/bin/bash
set -euo pipefail

cat > /app/fasttext.py <<'PYEOF'
import json, math

words = []
vectors = {}
with open('/app/model.vec') as f:
    vocab_size, dim = map(int, f.readline().split())
    for line in f:
        parts = line.split()
        if not parts:
            continue
        w = parts[0]
        vec = [float(x) for x in parts[1:]]
        words.append(w)
        vectors[w] = vec

def dot(a, b):
    return sum(x * y for x, y in zip(a, b))

def norm(a):
    return math.sqrt(dot(a, a))

def cos(a, b):
    return dot(a, b) / (norm(a) * norm(b))

q = vectors['queen']
best_word, best_score = None, -2.0
for w in words:
    if w == 'queen':
        continue
    s = cos(q, vectors[w])
    if s > best_score + 1e-9 or (abs(s - best_score) < 1e-9 and best_word is None):
        best_score = s
        best_word = w
    if s > best_score:
        best_score = s
        best_word = w

out = {
    'vocab_size': vocab_size,
    'dim': dim,
    'queen_vector': [round(x, 4) for x in q],
    'nearest': best_word,
}
with open('/app/similar.json', 'w') as f:
    json.dump(out, f)
PYEOF

python3 /app/fasttext.py