#!/bin/bash
set -euo pipefail

cat > /app/similarity.py <<'PY'
import json
from sentence_transformers import SentenceTransformer

model = SentenceTransformer('/app/model_cache')
lines = open('/app/sentences.txt', encoding='utf-8').read().splitlines()
assert len(lines) == 2, lines
a, b = lines[0], lines[1]
va, vb = model.encode([a, b], normalize_embeddings=True, batch_size=16)
sim = float((va * vb).sum())
out = {"cosine_similarity": round(sim, 4)}
open('/app/similarity.json', 'w', encoding='utf-8').write(json.dumps(out))
print(json.dumps(out, ensure_ascii=False))
PY

python3 /app/similarity.py