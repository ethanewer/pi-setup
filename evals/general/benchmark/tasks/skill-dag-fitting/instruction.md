At `/app/edges.txt` is a description of a **directed acyclic graph (DAG)**. Each line is `u v` meaning there is a directed edge from node `u` to node `v`. Node ids are positive integers. The graph is guaranteed to be acyclic. A node id appears in the edge file only if it is an endpoint of some edge.

Write `/app/dag.py` that:
1. reads `/app/edges.txt`,
2. builds the DAG,
3. computes both of the following:
   - a **topological ordering** via Kahn's algorithm, choosing at each step the smallest available node id among zero-in-degree nodes,
   - the **length of the longest path** (in **number of edges**; a node with no incoming edges has longest-path length 0).
4. writes `/app/dag_result.json`:
   ```json
   {"longest_path_length": <int>, "order": [<int>, ...]}
   ```

For the given file the expected values are `longest_path_length = 4` and the lexicographic topological order `[1, 2, 3, 4, 5, 6]`. Use only the Python standard library. Run `/app/dag.py` so the output file exists.