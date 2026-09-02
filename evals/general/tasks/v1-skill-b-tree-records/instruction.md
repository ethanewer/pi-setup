A B-tree keeps keys sorted in a balanced tree and is a common structure for indexing and record management. In this task an in-memory B-tree has been serialized to JSON at `/app/btree.json`.

Format of the JSON:
```python
{"order": 4, "root": <node>}
```
Each node has the shape:
- leaf: `{"keys":[int,...], "children":[], "leaf":true}`
- internal: `{"keys":[...], "children":[<node>, ...]}`

A non-leaf node with `k` keys has exactly `k+1` children. The child at position 0 holds every key smaller than keys[0]; the child at position i (1<=i<=k) holds keys between keys[i-1] and keys[i]; the last child holds keys greater than keys[k-1]. Keys within a node are unique and strictly ascending, and the whole tree respects B-tree ordering.

Write a program `/app/scan_btree.py` that:
1. loads `/app/btree.json`,
2. performs an in-order traversal of the whole tree, collecting every key exactly once in ascending order,
3. writes the keys, one per line, to `/app/sorted_keys.txt`.

Run your program so the output file is created. The file must list exactly the sorted sequence of all keys present in the tree.
