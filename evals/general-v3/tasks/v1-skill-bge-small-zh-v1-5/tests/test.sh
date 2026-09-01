#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/embed.json" ] && [ -f "$APP/similarity.json" ]; then
  if python3 - "$APP" <<'PYEOF'
import json, math, sys
base = sys.argv[1]
data = json.load(open(base + '/embed.json'))
sents = data['sentences']
vecs = data['embeddings']
def cosine(a, b):
    num = sum(x*y for x, y in zip(a, b))
    na = math.sqrt(sum(x*x for x in a))
    nb = math.sqrt(sum(x*x for x in b))
    if na == 0 or nb == 0:
        return 0.0
    return num / (na * nb)
exp = []
for i in range(len(sents)):
    best = -1.0; bestj = -1
    for j in range(len(sents)):
        if i == j: continue
        s = cosine(vecs[i], vecs[j])
        if bestj == -1 or s > best + 1e-12 or (abs(s - best) <= 1e-12 and j < bestj):
            bestj = j; best = s
    exp.append({'sentence': sents[i], 'closest': sents[bestj], 'score': round(best, 4)})
got = json.load(open(base + '/similarity.json'))
ok = len(got) == len(exp)
if ok:
    for a, b in zip(got, exp):
        if a.get('sentence') != b['sentence'] or a.get('closest') != b['closest']:
            ok = False
        try:
            if abs(float(a.get('score')) - b['score']) > 1e-6:
                ok = False
        except Exception:
            ok = False
sys.exit(0 if ok else 1)
PYEOF
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt