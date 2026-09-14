# limber-cinder — notes for working in this container

You are inside a trial image for a debugging task built on the real
**Jinja** codebase (`pallets/jinja`).

## What is installed and where

- The repository is checked out, detached, at `/app/src` (the working tree
  starts clean). Do **not** commit, fetch, push, or otherwise modify the
  `.git` directory inside it.
- Jinja is installed from that tree with an **editable install**: a plain
  `.pth` in `site-packages` points `import jinja2` back at
  `/app/src/src/jinja2`. Consequence: changing the source under
  `/app/src/src/jinja2/` is exactly what the interpreter sees on the very
  next run — no rebuild or reinstall step exists.
- `python3` is Python 3.12. `pytest` 7.4.3 is installed. `markupsafe`
  3.0.3 is the pinned dependency.
- There is **no network** and only **one vCPU**; nothing else is needed.

## Running the project's tests

The project's own tests live in `/app/src/tests/` and are self-contained:

```sh
cd /app/src
python3 -m pytest tests/test_api.py::TestUndefined -q   # seconds
```

Do not try to run the whole suite: at this development-era snapshot two
files fail for reasons unrelated to this task (`tests/test_debug.py`
asserts an old traceback format, `tests/test_loader.py` uses a pytest
module-teardown API removed in pytest 7). Everything else passes.

## A quick sanity probe

```sh
cd /app/src && python3 -c "import jinja2; print(jinja2.__file__)"
# -> /app/src/src/jinja2/__init__.py
```

## Deliverables

Your task prompt describes the deliverables. In short: write
`/app/repro.py` (your own failing reproduction), then fix the defect in the
tree at `/app/src`, and write `/app/summary.md`. Keep scratch files under
`/tmp` and delete them when done — the graded tree must differ from the
pinned commit **only** in the source file where the bug lives.