#!/usr/bin/env bash
set -euo pipefail
cat > /app/turtle.py <<'PYEOF'
import json
from rdflib import Graph
g = Graph()
g.parse('/app/data/people.ttl', format='turtle')
g.serialize('/app/ntriples.nt', format='nt')
preds = sorted({str(p) for _, p, _ in g})
result = {'predicates': preds, 'count': len(set(g))}
with open('/app/result.json', 'w') as f:
    json.dump(result, f)
PYEOF
python3 /app/turtle.py