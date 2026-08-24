# Querying an RDF ontology with SPARQL

`/app/data.ttl` is a small RDF graph in **Turtle** syntax. It describes four
people (`ex:alice`, `ex:bob`, `ex:carol`, `ex:dave`), each typed as a
`foaf:Person`, with a `foaf:name`, an `ex:age` (an integer literal), and a
`foaf:knows` relationship to one other person.

The container has the `rdflib` Python package installed.

## Task

Write a Python script `/app/query.py` that:

1. Parses `/app/data.ttl` into an RDF graph.
2. Runs a SPARQL query that finds every `foaf:Person` whose `ex:age` is
   **greater than or equal to 30**, and projects their `foaf:name`.
3. Orders the result names **alphabetically (ascending)**.
4. Writes exactly those names to `/app/results.txt`, **one per line**, in that
   sorted order (UTF-8, final newline optional).

Run the script so that `/app/results.txt` exists. Only the two qualifying people
(currently Alice and Carol) should appear, sorted. The verifier independently
parses the same Turtle file and compares against `/app/results.txt`.