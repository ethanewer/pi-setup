# outrigger-ferry

You are inside a real checkout of **Poetry** (`python-poetry/poetry`) at a
pinned historical commit in `/app/src`, installed editable into the venv at
`/opt/poetry-venv`.

Reproduce the defect with your own failing script `/app/repro.py` **before**
changing any source, fix it in the tree, and write `/app/summary.md`.

See `instruction.md` (sibling of this file, mounted at the task root) for
the full brief.

- The tree is the deliverable; only the source file where the bug lives may
  differ from the pinned commit's bytes.
- Harness-owned paths: `/opt/golden`, `/opt/pre-fix-poetry`, `/tests`,
  `/solution`. Do not touch them.
- No network. `cpus = 1`.