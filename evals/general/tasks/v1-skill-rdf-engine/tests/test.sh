#!/usr/bin/env bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

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