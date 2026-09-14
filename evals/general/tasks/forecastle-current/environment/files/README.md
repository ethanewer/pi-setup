# forecastle-current

Task workspace.

- `/app/src` — the pinned upstream HTTPX 0.27.0 checkout (the buggy revision),
  installed editable so edits under `/app/src` are live on the next import.
- `/app/reproduce.py` — your deliverable (you write it), per instruction.md.

The repository under `/app/src` is a real project: read it, run its tests,
find the bug, fix it in the library source.