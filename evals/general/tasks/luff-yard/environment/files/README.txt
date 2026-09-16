# /app

`/app/src` is a shallow, pinned clone of pallets/werkzeug — the WSGI utility
library that backs Flask — checked out in a detached state at one specific
upstream commit and installed in editable (development) mode, so
`import werkzeug` resolves to the checked-out source.

Your job is described in the task instruction. The two deliverables, both
under /app, are:

- the repaired `/app/src` tree, and
- `/app/reproduce_www_authenticate_bug.py` — your own failing reproduction,
  which you must write and confirm fails *before* you change any code.

`/opt/golden`, `/tests` and `/solution` are harness-owned; do not touch them.
There is no network at trial time.