#!/bin/bash
set -euo pipefail

cat > /app/query.py <<'PY'
from rdflib import Graph, Namespace

EX = Namespace('http://example.org/')
FOAF = Namespace('http://xmlns.com/foaf/0.1/')

g = Graph()
g.parse('/app/data.ttl', format='turtle')

q = '''
PREFIX ex: <http://example.org/>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
SELECT ?name WHERE {
  ?p a foaf:Person ;
     foaf:name ?name ;
     ex:age ?age .
  FILTER(?age >= 30)
}
ORDER BY ?name
'''
rows = sorted(str(r[0]) for r in g.query(q))
open('/app/results.txt', 'w').write('\n'.join(rows) + '\n')
print('results:', rows)
PY

python3 /app/query.py