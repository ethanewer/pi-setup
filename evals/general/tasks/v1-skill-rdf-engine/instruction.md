# RDF engine (triple store + SPARQL)

The Python package **`rdflib`** is installed in this environment. `/app/data/triples.nt`
is an N-Triples RDF document:

```
<http://example.org/alice> <http://example.org/name> "Alice" .
<http://example.org/bob> <http://example.org/name> "Bob" .
<http://example.org/alice> <http://example.org/age> "30"^^<http://www.w3.org/2001/XMLSchema#integer> .
<http://example.org/charlie> <http://example.org/name> "Charlie" .
<http://example.org/bob> <http://example.org/knows> <http://example.org/alice> .
```

Write `/app/rdf.py` that:

1. Loads the document into an rdflib `Graph` (parse as `format="nt"`).
2. Runs a SPARQL `SELECT` that finds every object of the predicate
   `<http://example.org/name>`.
3. Sorts those name strings alphabetically.
4. Counts the **total number of triples** in the graph.
5. Writes `/app/result.json`:

```json
{"names": ["Alice", "Bob", "Charlie"], "total_triples": 5}
```

Run `python3 /app/rdf.py` so the file is produced. The verifier recomputes both
values from `triples.nt`; do not hardcode.