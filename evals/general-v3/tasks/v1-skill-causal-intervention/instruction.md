/app/graph.json contains a causal graph as `nodes` (alphabetical list) and `edges` (map from a cause node to the list of its direct effects). For example an edge means "the left node is a direct cause of the right node".

In causal reasoning, intervening on (setting) a node can only influence nodes downstream along **directed paths**; a node whose directed path cannot reach the target is unaffected by, and cannot influence, the target.

The JSON has the form:

```json
{
  "nodes": ["A", "B", ...],
  "edges": {"A": ["B", ...], "B": ["D"], ...},
  "target": "D"
}
```

Write `/app/causal.py` that reads the graph and determines, for **every variable except the target**, whether that variable has at least one directed path (following edges) to the target. Then it writes `/app/cannot_reach.json` containing exactly:

```json
{"cannot_reach_target": ["<nodes (excluding the target) with NO path to the target, in the order they appear in \"nodes\">", ...]}
```

Then run your script so `/app/cannot_reach.json` is produced. Use only the Python standard library.