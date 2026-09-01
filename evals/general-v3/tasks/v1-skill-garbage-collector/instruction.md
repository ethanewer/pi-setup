You are implementing a **mark-sweep garbage collector** for a virtual heap.

In `/app/heap.json` there is a graph-shaped object heap. The JSON object has two fields:

- `"roots"`: a list of object ids referenced from the program stack (always alive).
- `"objects"`: a JSON object mapping each object id to a list of object ids that it points to (its outgoing references). Some objects are not reachable from any root.

Garbage collection works by **marking** every object reachable from the roots (following outgoing references), then **sweeping** (collecting) all unmarked objects as garbage.

Write `/app/gc.py` that:
1. Reads `/app/heap.json`.
2. Runs mark-sweep: mark the roots and everything transitively reachable from them.
3. Writes `/app/collected.json` containing a JSON array of the collected (garbage) object ids, **sorted lexicographically**:
```json
["d", ...]
```

Run your script so `/app/collected.json` lists exactly the unreachable objects. Use `python3`.