# Ontology traversal

`/app/ontology.json` describes a small **taxonomy (hierarchical ontology)** as a DAG:

```json
{
  "nodes": [{"id": "...", "name": "..."}, ...],
  "edges": [{"child": "...", "parent": "...", }, ...]
}
```

Each `edges` entry says the `child` node is a direct sub-class of the `parent` node.
The graph is a DAG (no cycles). Example entries: `{"child": "wolf", "parent": "canis"}`,
`{"child": "canis", "parent": "canidae"}`, ... up to `"organism"`, the single root.

Write a Python script `/app/traverse.py` that:

1. loads the ontology from `/app/ontology.json`,
2. performs an **ancestor traversal** starting from the node with `id == "wolf"`:
   walk `parent` links transitively (wolf -> canis -> canidae -> carnivora -> mammal ->
   vertebrate -> animal -> organism),
3. collects **all ancestors of "wolf"** (the node itself is NOT included), deduplicated,
4. writes to `/app/ancestors.txt` the **names** of those ancestors, one per line, sorted
   **alphabetically (ascending)**.

Run your script so `/app/ancestors.txt` exists. The verifier performs the same traversal
independently and compares the sorted list of names.