# Fix the socket-waiting crash in the psycopg checkout

A real upstream checkout of the **psycopg** PostgreSQL adapter (the pure
Python `psycopg` package, version 3.3.5.dev1) lives at `/app/src`. It is
faithful to the upstream project at a known historical state — complete with
a genuine bug that upstream later fixed. Your job is to find the bug,
understand it, and repair the library so the behavior described below holds.

## The user-visible symptom

Connecting to a database is a multi-phase operation: psycopg first waits for
the connection socket to become **writable** (the OS has accepted the
connection), and once woken up it waits again for the socket to become
**readable** (the server's greeting has arrived). On platforms where psycopg
falls back to its generic selector-based socket waiting, any operation that
needs two consecutive waits on the *same* connection — like that connect —
dies mid-way instead of completing:

```python
>>> from psycopg import waiting
>>> import socket, selectors
>>> r, w = socket.socketpair()
>>> def gen():
...     yield selectors.EVENT_WRITE      # phase 1: wait until writable
...     yield selectors.EVENT_READ       # phase 2: wait for read after wake-up
...     return "COMPLETED"
>>> waiting.wait_selector(gen(), r.fileno(), interval=0.05)
Traceback (most recent call last):
  ...
KeyError: 3 (FD 3) is already registered
```

The wait loop keeps re-registering the same file descriptor after each
wake-up instead of updating its registration, so multi-phase operations crash
with `KeyError: ... is already registered` instead of completing. A
single-phase wait (one wait state, then done) happens to work, which is why
casual testing misses it.

The wait function completes only when the descriptor is re-registered
correctly between phases.

## Deliverable

Repair the checkout at `/app/src` so the repro above prints

```
returned: COMPLETED
```

and no exception escapes the wait call. The delivered artifact is the
repaired source tree itself: `/app/src` with your fix in it. The library
imports straight out of that tree (`PYTHONPATH=/app/src/psycopg` is preset
for every shell), so your edits take effect immediately:

```python
>>> import psycopg, psycopg.waiting
>>> psycopg.waiting.__file__   # resolves inside /app/src
```

There is no report file to write and nothing to install.

## Constraints

- The fix must live in the library source inside the checkout. Changing
  behavior from outside the tree (monkey-patching at test time, wrappers,
  environment variables) is not an acceptable repair.
- The tree is graded for *provenance*. Outside the minimal library change
  your fix requires, every tracked file under `/app/src` must remain
  byte-identical to the checked-out revision: do not edit any other file, and
  do not add files inside the repository tree — put scratch files under
  `/tmp` instead.
- Leave the repository at its checked-out revision (`HEAD` must stay where it
  is). Do not re-clone, fetch, or check out any other revision.
- There is no network at trial time. Everything you need is already in the
  image.

## Environment

- The checkout is at `/app/src` (a git repository, detached at the historical
  revision that still has the bug). The package source is under
  `/app/src/psycopg/psycopg/`.
- `psycopg` is importable from anywhere (editable install), resolving to the
  source tree. `libpq` and the pinned test tooling (`pytest` 9.1.1) are
  installed.
- The project's own unit tests are at `/app/src/tests`, runnable with the
  installed `pytest` from the repository root:

  ```bash
  cd /app/src && python3 -m pytest -q tests/test_waiting.py
  ```

  This repository's wait-function tests are self-contained — they use only
  localhost sockets, no database server is needed. The module most relevant
  to this bug is `tests/test_waiting.py`; read it to see the semantics the
  suite already locks in about the `wait_selector` function (what ready
  events a waiting generator is sent, and what happens on timeouts).

- Direct repro, run from anywhere:

  ```bash
  python3 - <<'EOF'
  import socket, selectors
  from psycopg import waiting
  r, w = socket.socketpair()
  def gen():
      yield selectors.EVENT_WRITE   # phase 1: wait until writable
      yield selectors.EVENT_READ    # phase 2: wait for read after wake-up
      return "COMPLETED"
  try:
      rv = waiting.wait_selector(gen(), r.fileno(), interval=0.05)
      print("returned:", rv)
  except Exception as ex:
      print(type(ex).__name__, "-", ex)
  EOF
  ```

  Today this prints `KeyError - 3 (FD 3) is already registered`. Your repair
  is complete when it prints `returned: COMPLETED` and the project's own
  waiting-test module passes.