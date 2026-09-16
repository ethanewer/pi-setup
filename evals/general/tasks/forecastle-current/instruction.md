# Client-level timeout silently ignored for requests passed to `client.send()`

## Environment

- **HTTPX 0.27.0** is checked out at **`/app/src`** from the pinned upstream
  repository and installed **editable**, so any edit you make under
  `/app/src` is live the next time a process does `import httpx`. The checkout
  is a git working tree: `git status`, `git diff`, `git log` and `git stash`
  all work. Do not rewrite history with `git reset --hard` or `git checkout`
  of other commits — there is no network, so you could not fetch anything back.
- The container has **no network**. Every dependency you need is already
  installed (`pytest`, `anyio`, `trio`, `uvicorn`, `trustme`,
  `cryptography`, `h2`, `brotli`, `socksio`, `chardet`). Do not try to
  `pip install` anything; it will fail.
- The machine is budgeted at one CPU. Everything here is pure Python, so the
  project's test runs finish in seconds.
- `/opt` and everything under it are immutable reference data owned by root;
  you cannot and must not modify them.

## The bug

Users of the library can build a request by hand — `httpx.Request("GET",
url)` — and hand it to the client with `client.send(request)`. The
documented contract is that the **client's own configuration**, including its
`timeout`, applies to such requests unless the request already carries its
own timeout.

That contract is broken. When the request is built by hand and passed to
`send()`, the client's configured timeout is **silently ignored**: the send
runs with the library's default timeout instead, so an operation that should
be aborted almost immediately (say 50 ms) instead hangs for the full default
period and then **succeeds anyway**. Programs that rely on a strict timeout
to fail fast are left waiting regardless of the value they configured.

This affects **both** the synchronous client and the asynchronous client:
`httpx.Client` and `httpx.AsyncClient`, `client.send(...)` and
`await client.send(...)`, with a request constructed directly as
`httpx.Request(...)`.

The correct behaviour:

1. A request handed to `client.send()` with no timeout of its own is bounded
   by the client's configured timeout. When the peer is slower than that
   timeout, the send must raise `httpx.TimeoutException` quickly — it must
   **not** wait the default period and succeed.
2. A request that **already carries its own timeout** (via `request.extensions`
   / `httpx.Timeout(...).as_dict()`) must still be governed by **that**
   request-level timeout, exactly as before: a request-level timeout wins over
   the client-level one.
3. Requests built through the client's own helpers (`client.get`,
   `client.post`, `client.build_request`, …) must keep behaving exactly as
   they do today.

## What you must deliver

### 1. `/app/reproduce.py` — your own failing reproduction (write this first)

Before you touch the library source, write a **self-contained, single-file**
reproduction that demonstrates the bug from outside. Requirements:

- Uses only the Python standard library and `httpx` (and its installed
  dependencies). Do not rely on sibling files, on `pytest`, or on anything
  outside a fresh interpreter.
- Starts a local HTTP server on `127.0.0.1` at a random port that delays
  each response before answering (e.g. ~0.25 s), just enough that a short
  client timeout should fire.
- Creates an `httpx.Client(timeout=...)` with a **short** timeout (well below
  the server's delay) and calls `client.send(...)` with a **manually built**
  `httpx.Request` — not the client's own builder.
- **Output contract** (the acceptance parses this exactly):
  - when the send **raised** `httpx.TimeoutException` because the client
    timeout was honoured: print a line **starting with `OK`** and exit `0`;
  - when the send **returned a response** (the timeout was ignored): print a
    line **starting with `BUG`** and exit nonzero.
- Must terminate on its own within 10 seconds in both cases (no infinite
  waits). Never block waiting for user input.
- Run it with plain `python3 /app/reproduce.py` from any directory.

On the tree as you found it, the script must print the `BUG` line and exit
nonzero. After your fix it must print the `OK` line and exit 0. The
acceptance runs your script against **both** a pristine pre-fix copy of the
library and your repaired tree, and requires exactly that behaviour in each
— so a canned script that always prints one answer cannot pass.

Write the reproduction first, run it, and confirm you can observe the bug
before you start fixing anything.

### 2. The fix, inside the library

Fix the bug in the package source under `/app/src/httpx` so that all three
points of the correct behaviour above hold. Where in the tree the fix lives,
what you name any new internal helper, and how you structure it are your
design decisions. A monkeypatch or wrapper imported at interpreter startup,
or a conftest/sitecustomize shim, is **not** a fix: the repaired behaviour
must come from the package source itself, and a fresh
`python3 -c "import httpx; ..."` must show it.

Do **not** modify anything under `/app/src/tests`. The acceptance pins the
entire clone in a build-time manifest: the shipped test fixtures and every
other file under `/app/src` must stay byte-identical except for the module
where the client classes implement `send()` — that is the only file your
fix may change. Editing or deleting a test, changing a config (e.g.
`pyproject.toml`), or adding any new file (e.g. a `conftest.py` or
`sitecustomize.py` that skips or rewrites the tests) fails the task. If you
are tempted to edit a test to make it pass, the honest move is to fix the
library instead.

### 3. Keeping the project's own suite green

The acceptance runs the project's own tests and they must all pass. Use
exactly these invocations as your bar while you work:

```bash
cd /app/src
python3 -m pytest tests/client/test_client.py tests/client/test_async_client.py -q -m "not network"
python3 -m pytest tests/test_timeouts.py -q -m "not network" -k "read_timeout or pool_timeout or new_request_send_timeout"
```

Notes on the two files:

- `tests/test_timeouts.py` contains the project's own regression test for the
  reported behaviour, `test_async_client_new_request_send_timeout`. It
  **fails on the pristine checkout — that is the expected starting state** —
  and must pass once you are done. The other selected tests in that file
  (`test_read_timeout`, `test_pool_timeout`) must stay green.
- `test_write_timeout` in that file trips an unrelated garbage-collection
  warning flake on the trio backend in this environment; it is not part of
  the acceptance bar, and neither is the network-marked connect test. Do not
  chase either of those.
- The async acceptance checks run under both the asyncio and trio backends
  (the project's `anyio` mark).

**Do not** change any existing public API signature.

## Deliverable summary

- `/app/reproduce.py` — required, exact output contract above.
- A real fix in `/app/src/httpx` — required.
- The project's own suite above staying green — required.

When you believe you are done, run the two pytest invocations above plus
`python3 /app/reproduce.py` one last time and confirm the reported results:
the suite passes and the reproduction flips from `BUG` to `OK`.