# Answer interventions in a dependency graph

You must write a reusable **Python program** `/app/solve.py` that computes, for
an arbitrary input (directed acyclic) dependency graph, a lexicographically
stable topological order and the value of every node after a set of interventions.

## Input files

`/app/graph.csv` — header line `parent,child`, then one `parent,child` edge per
line (comma-separated, no spaces). Every node mentioned appears either as a
parent, a child, or both. A node may be isolated (appears in `values.csv` only).
Tolerate a trailing empty line.

`/app/values.csv` — header `node,base`, then one `node,base` line per node,
where `base` is a decimal number (e.g. `10`, `2.5`, `0.333333333`). Every node
in `graph.csv` appears exactly once in `values.csv`, and every row names a real
node.

## Command-line interface

```
python3 /app/solve.py --graph <graph.csv> --values <values.csv> \
    [--intervention node=value [,node=value ...] ...] --output <out.json>
```

- `--intervention` may be repeated, or given as a comma-separated list of
  `node=value` pairs. It fixes a node to a value. An intervention naming a node
  not present in the graph is ignored.
- `--output` is the file path where the JSON result is written.

## Semantics

1. **Acyclicity.** If the graph is not acyclic (no topological order consumes
   every node), report it as cyclic.
2. **Lexicographic topological order.** Repeatedly choose, among all nodes whose
   parents have all already been emitted, the node with the **smallest name under
   ordinary alphabetical string comparison**, and emit it. Names are unique.
3. **Node values.** A non-intervened node's value equals its own `base` plus
   `0.5` times the value of **each of its parents** (parents already finalized in
   topological order). An intervened node **ignores its parents** and its value is
   exactly the intervention value (not the base).
4. **Arithmetic.** Use exact decimal arithmetic, and round every reported value to
   **six decimal places**, half-up (e.g. `0.1666666665` → `0.166667`).

## Result JSON (acyclic case)

```json
{
  "acyclic": true,
  "intervention": { "left": 10.0 },
  "order": ["root", "left", "right", "leaf"],
  "values": {
    "root": 4.0,
    "left": 10.0,
    "right": 5.0,
    "leaf": 8.5
  }
}
```

`intervention` is the map of node→value actually applied (only nodes that are
real and matched). `order` lists every node in the lexicographic topological
order. `values` has every node with its six-decimal-rounded value. Key order is
not significant.

## Cyclic case

For a cyclic graph the result must be exactly:

```json
{ "acyclic": false, "intervention": null, "order": null, "values": null }
```

## Produce the visible answer

Run your program on the shipped `/app/graph.csv` and `/app/values.csv` with the
intervention `left=10`, writing to `/app/answer.json`:

```
python3 /app/solve.py --graph /app/graph.csv --values /app/values.csv \
    --intervention left=10 --output /app/answer.json
```

The verifier also runs your program on **additional hidden inputs**: fresh graphs
(including nodes with no parents and isolated nodes), graphs with cycles, and
fractional / rounding-heavy cases. `/app/solve.py` must work for any input
following the documented shape.

## Do not modify

Do not modify, rename, or delete `/app/graph.csv` or `/app/values.csv`. Only
write files under `/app`. Leave `/app/solve.py` and `/app/answer.json` behind.