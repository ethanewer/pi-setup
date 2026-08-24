#!/bin/bash
mkdir -p /logs/verifier

reward=0

if [ ! -f /app/retrieve.py ] || [ ! -s /app/retrieve.py ]; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

# The main check runs the script (twice for determinism) and recomputes expected values.
cat > /tmp/verify_048.py <<'PYEOF'
import json, sys, os, subprocess

data = '/app/data'
def read_text(path):
    return open(path, 'r', encoding='utf-8').read().split('\n')

pinned_src = open('/app/MODEL_SHA.txt', 'r', encoding='utf-8').read().strip()
pinned = pinned_src[len('sha='):] if pinned_src.startswith('sha=') else pinned_src

docs = read_text(data + '/docs.txt')
if docs and docs[-1] == '': docs = docs[:-1]
queries = read_text(data + '/queries.txt')
if queries and queries[-1] == '': queries = queries[:-1]
truth = json.load(open(data + '/ground_truth.json', encoding='utf-8'))

# Independent recomputation from the same snapshot / procedure.
from sentence_transformers import SentenceTransformer
import numpy as np
model = SentenceTransformer('/app/model_cache')
QP = '为这个句子生成表示以用于检索相关文章：'
demb = model.encode(docs, normalize_embeddings=True, batch_size=16)
qemb = model.encode([QP + q for q in queries], normalize_embeddings=True, batch_size=16)
sims = qemb @ demb.T

exp = {}
for qi, scores in enumerate(sims):
    qid = qi + 1
    order = sorted(range(len(docs)), key=lambda di: (-float(scores[di]), di))
    rel = int(truth[str(qid)])
    exp[qid] = (order.index(rel - 1) + 1, order[0] + 1)

if not os.path.exists('/app/ranks.jsonl'):
    print('REWARD 0')
    sys.exit(0)

lines = [l for l in open('/app/ranks.jsonl', encoding='utf-8').read().split('\n') if l.strip()]
ok = True
reason = []
if len(lines) != len(queries):
    ok = False
    reason.append('line_count')

rank_map = {}
try:
    for l in lines:
        o = dict(json.loads(l))
        rank_map[o.get('query_id')] = o
    if len(rank_map) != len(queries):
        ok = False
        reason.append('query_ids')
except Exception:
    ok = False
    reason.append('json_parse')

for qid in sorted((int(k) for k in truth), key=int):
    if qid not in rank_map:
        ok = False
        reason.append(f'missing_{qid}')
        continue
    o = rank_map[qid]
    er, etop = exp[qid]
    if o.get('rank_of_relevant') != er:
        ok = False
        reason.append(f'rank_{qid}')
    if o.get('top_doc_id') != etop:
        ok = False
        reason.append(f'top_{qid}')
    if str(o.get('pinned_sha', '')).replace('sha=', '') != pinned:
        ok = False
        reason.append(f'sha_{qid}')
    if o.get('relevant_doc_id') != int(truth[str(qid)]):
        ok = False
        reason.append(f'rel_{qid}')

# Determinism: rerun and compare.
p1 = open('/app/ranks.jsonl', encoding='utf-8').read()
subprocess.check_call(['python3', '/app/retrieve.py'])
p2 = open('/app/ranks.jsonl', encoding='utf-8').read()
if p1 != p2:
    ok = False
    reason.append('nondeterministic')

if ok:
    print('REWARD 1')
else:
    print('REWARD 0')
    if reason:
        print('REASON ' + ','.join(reason), file=sys.stderr)
PYEOF

res=$(python3 /tmp/verify_048.py)
reward=$(echo "$res" | grep -o 'REWARD [0-9.]*' | head -1 | sed 's/REWARD //')
if [ -z "$reward" ]; then
  reward=0
fi

echo "$reward" > /logs/verifier/reward.txt