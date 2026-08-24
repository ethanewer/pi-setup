#!/usr/bin/env bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ]; then
  if python3 - <<'PY'
import json, sys
from rdflib import Graph, URIRef
g = Graph()
g.parse("/app/data/triples.nt", format="nt")
name = URIRef("http://example.org/name")
names = sorted(str(obj) for s, p, obj in g if p == name)
count = len(list(g))
res = json.load(open("/app/result.json"))
ok = (res.get("names") == names) and (int(res.get("total_triples")) == count)
sys.exit(0 if ok else 1)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt