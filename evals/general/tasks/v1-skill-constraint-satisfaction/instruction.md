`/app/graph.json` describes a small map-coloring problem:
```json
{"colors": ["red", "green", "blue"], "regions": ["north", "south", "east", "west"], "adjacency": [["north","south"],["north","west"],["south","east"],["south","west"]]}
```

You must find an assignment of a color to each region such that **no two adjacent regions share the same color**. This is a classic constraint-satisfaction problem (CSP) over a small domain of 3 colors and 4 regions.

Write a program `/app/color.py` that:
1. loads `/app/graph.json`,
2. does a backtracking search over the regions assigning a color from the `colors` list,
3. respects the `adjacency` constraints (regions appearing together must get different colors),
4. writes the found assignment to `/app/assignment.json` as a JSON object mapping every region name to a color name (e.g. `{"north":"red", ...}`).

Run `/app/color.py` so `/app/assignment.json` is produced. The verifier re-reads `graph.json`, validates that every region has a color from the allowed set and that all adjacency constraints hold, and requires `assignment.json` to be well-formed JSON. Any valid coloring with all regions assigned is accepted.