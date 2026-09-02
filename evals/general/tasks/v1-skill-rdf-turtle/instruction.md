# RDF/Turtle parsing

The Python package **`rdflib`** is installed in this environment. `/app/data/people.ttl`
is a Turtle RDF file with a prefix declaration:

```turtle
@prefix ex: <http://example.org/> .

ex:alice ex:name "Alice" ;
       ex:age 30 .
ex:bob ex:name "Bob" .
ex:carol ex:knows ex:alice .
```

(i.e., at `/app/data/people.ttl`)

Write `/app/turtle.py` that:

1. Parses `people.ttl` into an rdflib `Graph` (parse with default/`format="turtle"`).
2. Expands every triple to full (unabbreviated) IRIs by serializing the graph back
   to N-Triples into `/app/ntriples.nt` (`graph.serialize(..., format="nt")`).
3. Collects the full-IRI strings of all distinct predicates (as absolute IRI strings).
4. Sorts them alphabetically.
5. Counts the total number of triples.
6. Writes `/app/result.json`:

```json
{
  "predicates": ["http://example.org/age", "http://example.org/knows", "http://example.org/name"],
  "count": 4
}
```

Run `python3 /app/turtle.py` so both output files are produced. The verifier
re-parses both `people.ttl` and your `ntriples.nt` and requires they contain the
same set of triples; do not hardcode.