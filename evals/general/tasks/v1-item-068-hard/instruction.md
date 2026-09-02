# Querying a small social ontology with SPARQL

`/app/ontology.ttl` is a small RDF graph in Turtle. It declares five
`foaf:Person` entities (`ex:alice`, `ex:bob`, `ex:carol`, `ex:dave`,
`ex:eve`). Each person has:
- `foaf:name` (a literal string),
- `ex:age` (a typed integer literal),
- `ex:knows` (points to another person).

Write a Python 3 script `/app/answer.py` that loads this graph with `rdflib`
and runs SPARQL queries to produce **three** deterministic output files.

## Deliverables

### 1) `/app/results.txt` — filtered traversal, sorted

Every `foaf:Person` whose `ex:age` is **greater than or equal to 30**, ordered
by `foaf:name` in ascending (byte/lexicographic) order. Write the names one per
line, in that order.

### 2) `/app/connections.json` — cardinality & duplicates

Count the **distinct** `ex:knows` subject→object edges, and count the
**distinct** people (distinct subjects typed `foaf:Person`). Emit exactly:

```json
{"knows_edges": <count>, "distinct_people": <count>}
```

The counts must be **distinct** (duplicate triples must not be double-counted).

### 3) `/app/oldest.json` — aggregation

Find the person with the **maximum** `ex:age`. Emit exactly:

```json
{"name": "Carol", "age": 40}
```

with that person's `foaf:name` and `ex:age` (if several tie, take the one whose
`foaf:name` sorts first). The container has `rdflib` installed.

The verifier independently parses the same Turtle file, re-runs equivalent
queries, and compares all three files:
- `/app/results.txt` line-for-line,
- both JSON objects field-for-field.

Read the ontology header before writing your joins — names, ages, and the
`knows` edges are all present exactly once per triple above.