mooring-port
============

What is where:

- `/app/src` — a shallow, pinned clone of the Pylint source repository
  (https://github.com/pylint-dev/pylint) at the upstream commit named in the
  instruction, installed in editable mode: `python3 -m pylint` runs this tree.
- `/app` — your working area; your reproduction deliverable must be written to
  the literal path `/app/reproduce.py`.
- `/opt/golden` — harness-owned copy of upstream regression tests; do not touch.
- `/tests` and `/solution` — harness-owned; do not touch.

Environment: Python 3.12.13. `pytest`, the project's own test dependencies
(astroid 4.2.0b5, pytest 8.4.1, ...) are installed. There is no network at
trial time.

The repository root contains the project's own `pylintrc`, which is picked up
automatically when Pylint runs with `/app/src` as the working directory and
enables the project's extension plugins.

Run the project's own tests like this (from `/app/src`):

    python3 -m pytest tests/test_functional.py -k "typing or redundant_typehint" -o addopts="" -q -p no:cacheprovider