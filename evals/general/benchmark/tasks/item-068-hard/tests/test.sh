#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/results.txt ] && [ -f /app/connections.json ] && [ -f /app/oldest.json ]; then
  if python3 - <<'PYEOF'
import json
from rdflib import Graph

g = Graph()
g.parse('/app/ontology.ttl', format='turtle')

rows = []
for name, age in g.query('''
PREFIX ex: <http://example.org/>
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
PREFIX dcterms: <http://purl.org/dc/terms/>
SELECT ?name ?age WHERE {
  ?p a foaf:Person ; foaf:name ?name ; ex:age ?age .
  FILTER(?age >= 30)
}
'''):
    rows.append((str(name), int(age)))
rows.sort(key=lambda r: r[0])
exp_rows = [n for n, _ in rows]

got_rows = [ln for ln in open('/app/results.txt').read().splitlines() if ln.strip() != '']
assert got_rows == exp_rows, (got_rows, exp_rows)

edges = set()
for a, b in g.query('''
PREFIX ex: <http://example.org/>
SELECT ?a ?b WHERE { ?a ex:knows ?b }
'''):
    edges.add((str(a), str(b)))
persons = set()
for p in g.query('''
PREFIX foaf: <http://xmlns.com/foaf/0.1/>
SELECT ?p WHERE { ?p a foaf:Person }
'''):
    persons.add(str(p[0]))
exp_conn = {'knows_edges': len(edges), 'distinct_people': len(persons)}
got_conn = json.load(open('/app/connections.json'))
assert got_conn == exp_conn, (got_conn, exp_conn)

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
exp_old = {'name': oldest[0], 'age': oldest[1]}
got_old = json.load(open('/app/oldest.json'))
assert got_old == exp_old, (got_old, exp_old)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt