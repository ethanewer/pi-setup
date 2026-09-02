#!/bin/bash
set -euo pipefail

cat > /app/query.py <<'PY'
import json
from rdflib import Graph, Namespace

EX = Namespace('http://example.org/')
FOAF = Namespace('http://xmlns.com/foaf/0.1/')

g = Graph()
g.parse('/app/ontology.ttl', format='turtle')

# 1) results.txt: names of persons with age >= 30, ascending name order
rows = []
for name, age in g.query('''
PREFIX ex: <http://example.org/>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
SELECT ?name ?age WHERE {
  ?p a foaf:Person ; foaf:name ?name ; ex:age ?age .
  FILTER(?age >= 30)
}
'''):
    rows.append((str(name), int(age)))
rows.sort(key=lambda r: r[0])
with open('/app/results.txt', 'w') as f:
    f.write('\n'.join(n for n, a in rows) + ('\n' if rows else ''))

# 2) distinct known edges, distinct persons
edges = set()
for a, b in g.query('''
PREFIX ex: <http://example.org/>
SELECT ?a ?b WHERE { ?a ex:knows ?b . }
'''):
    edges.add((str(a), str(b)))
persons = set()
for p in g.query('''
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
SELECT ?p WHERE { ?p a foaf:Person }
'''):
    persons.add(str(p[0]))
with open('/app/connections.json', 'w') as f:
    json.dump({'knows_edges': len(edges), 'distinct_people': len(persons)}, f)

# 3) oldest
oldest = None
for name, age in g.query('''
PREFIX ex: <http://example.org/>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
SELECT ?name ?age WHERE {
  ?p a foaf:Person ; foaf:name ?name ; ex:age ?age .
}
'''):
    cand = (str(name), int(age))
    if oldest is None or cand[1] > oldest[1] or (cand[1] == oldest[1] and cand[0] < oldest[0]):
        oldest = cand
with open('/app/oldest.json', 'w') as f:
    json.dump({'name': oldest[0], 'age': oldest[1]}, f)

print('adults', rows)
print('connections', {'knows_edges': len(edges), 'distinct_people': len(persons)})
print('oldest', oldest)
PY

python3 /app/query.py