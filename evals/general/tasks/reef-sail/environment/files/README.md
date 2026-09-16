# reef-sail environment

This task ships no starter source files beyond this note. Read the task
instruction (mounted by the harness) for the full contract.

What is already in the image:

- `/app/src` - a shallow, pinned clone of sqlalchemy/sqlalchemy at one
  specific upstream revision, installed from that tree in editable mode
  (importing `sqlalchemy` loads the source under `/app/src/lib`).
- Python 3.12, pytest, pytest-xdist, greenlet, typing-extensions.

Deliverables you must produce:

- `/app/reproduce_check_constraints.py` - your own failing reproduction
  script (see the instruction for its required exit contract),
- the repaired checkout at `/app/src`.

Harness-owned paths (`/opt/golden`, `/tests`, `/solution`) are off limits:
do not read from or write to them.