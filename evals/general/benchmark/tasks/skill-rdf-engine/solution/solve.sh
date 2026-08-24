#!/usr/bin/env bash
set -euo pipefail

cat > /app/rdf.py <<'PY'
import json
from rdflib import Graph, URIRef

g = Graph()
g.parse('/app/data/triples.nt', format='nt')
name = URIRef('http://example.org/name')
names = sorted(str(obj) for s, p, obj in g if p == name)
count = len(list(g))

with open('/app/result.json', 'w') as f:
    json.dump({'names': names, 'total_triples': count}, f)
PY

python3 /app/rdf.py