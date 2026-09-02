# Traverse a filesystem tree

`/app/tree/` is a nested directory tree (no symlinks, no hidden files):

```
tree/
|-- a.txt
|-- sub1/
|   |-- b.log
|   |-- empty/
|   `-- sub2/
|       |-- c.txt
|       `-- d.log
`-- sub3/
    `-- e.csv
```

## Your task

Write a Python 3 script `/app/traverse.py` that recursively walks the entire
tree rooted at `/app/tree/` (including all nested subdirectories) and computes:

- `dirs` — number of subdirectories under `/app/tree/` (not counting the root
  directory `/app/tree` itself),
- `files` — total number of files (regular files) under the tree,
- `total_bytes` — sum of the byte sizes of all regular files,
- `log_files` — number of files whose name ends in `.log`,
- `log_bytes` — sum of the byte sizes of the `.log` files.

Write `/app/tree.json` with exactly:

```json
{"dirs": 4, "files": 5, "total_bytes": 150, "log_files": 2, "log_bytes": 60}
```

Run the script so the JSON exists. The verifier recomputes every value with an
independent recursive walk and compares.