#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ] && [ -f /app/ntriples.nt ]; then
  if python3 - <<'PYEOF'
import json, sys
from rdflib import Graph

g1 = Graph(); g1.parse('/app/data/people.ttl', format='turtle')
g2 = Graph(); g2.parse('/app/ntriples.nt', format='nt')
res = json.load(open('/app/result.json'))
exp_preds = sorted({str(p) for _, p, _ in g1})
ok = (set(g1) == set(g2)
      and res.get('predicates') == exp_preds
      and int(res.get('count')) == len(set(g1)))
sys.exit(0 if ok else 1)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt
