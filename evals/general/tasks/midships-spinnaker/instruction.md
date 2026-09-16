# Task: fix a streaming-body regression in the `requests` HTTP library

## Context

`requests` (a real, widely-used Python HTTP client) is installed **editable**
from `/app/src` in this container: `import requests` resolves to
`/app/src/src/requests`, so any edit you make to that source tree takes effect
immediately — no reinstall is needed. The tree is a git clone pinned at the
exact upstream commit that contains the bug described below (there is no
network; do not attempt `git fetch`/`pip install`, and do not create commits —
leave changes as working-tree edits).

## The user-visible symptom

Many libraries produce **lazy file / stream proxy** objects: an object that
wraps a real open stream (a file, a `BytesIO`, a socket-like reader) and
forwards attribute access on itself to the wrapped stream — typically through a
single forwarded-lookup hook — so that `read()`, `seek()`, `tell()`, and the
rest behave exactly like the underlying stream. Such objects are perfectly
readable streams and are routinely passed to HTTP clients as request bodies.

Passing such a proxy object as the **request body** of a POST/PUT does not work
with this commit of `requests`. Two symptoms are reported by users:

1. Preparing the request fails outright with
   `TypeError: '<Proxy>' object is not iterable` — the failure happens during
   request preparation, before any bytes are sent. The same object works fine
   when handed to other HTTP clients, and a plain `BytesIO`/file object works
   fine with `requests`.
2. Even when preparation happens to succeed, following a **307 redirect**
   re-posts the request body *empty*: the server receives an empty body the
   second time.

The net effect: readable streaming bodies that are delivered through an
attribute-forwarding wrapper cannot be sent, although the library's own
documentation says any file-like object may be passed as a body.

## What you must do

### 1. Write a reproduction: `/app/reproduce.py`

Write a standalone Python script at `/app/reproduce.py` that **reproduces the
failure yourself** on the buggy library, and that unambiguously shows the bug
is gone once the library is fixed. Requirements:

- It must take **no arguments** and use only the installed `requests` plus the
  Python standard library.
- It must build a body of the kind described above — a stream-wrapper object
  that forwards attribute lookups to a wrapped stream — and pass it as the
  request body via `requests`' normal request-building API.
- When the bug is present, it must **fail** (an exception must propagate, so
  the process exits nonzero).
- When the library is fixed, it must exit **0** and print a line that starts
  with exactly `REPRO-OK` (anything may follow on the same line), demonstrating
  that the wrapped body is recognized as a streaming body and is passed through
  unchanged.

The verifier will run your `/app/reproduce.py` twice: once against a pristine
copy of the original (unfixed) source — where it must fail — and once against
your repaired tree — where it must print `REPRO-OK` and exit 0.

### 2. Fix the library in `/app/src`

Repair the bug in the `requests` source under `/app/src` (the real code, not a
wrapper at the reproduction level). After your fix:

- the reproduction succeeds as described above,
- a POST with such a wrapped streaming body survives a 307 redirect with the
  body re-sent intact.

Constraints:

- Change only the project source under `/app/src`; do **not** add or rename
  files outside repairs to the existing source layout, and do not create
  commits. The verifier compares the tree against the pinned commit: every
  tracked file except the one containing the root cause must remain
  byte-for-byte identical, and no stray untracked files may be added.
- The fix must be minimal and in the correct place: the root cause is a single
  flawed classification decision that decides whether a body is treated as a
  stream or as encodeable form data. Fix the classification so that
  attribute-forwarding stream wrappers are classified as streams.
- Do not weaken, delete, or alter the project's own tests.

### 3. Verify

Before finishing, run your reproduction against your repaired tree and confirm
`REPRO-OK`, e.g.:

```bash
python3 /app/reproduce.py
```

You may also run parts of the project's own test suite offline
(`python3 -m pytest /app/src/tests/...`); a local httpbin server is available
through `pytest-httpbin` if you want to exercise a real 307 redirect.

## What the grader checks

1. `/app/reproduce.py` fails on the pristine unfixed source and prints
   `REPRO-OK` (exit 0) on your fixed tree.
2. The upstream regression test for this bug (a POST of a wrapped stream
   through a 307 redirect against a local httpbin) passes against your tree.
3. Hidden cases with different payloads, methods, and wrapper shapes (including
   a large body) pass, and the body bytes arrive intact after the redirect.
4. A subset of the project's own existing test suite still passes (nothing
   else broke).
5. The tree is still at the pinned commit with only the minimal intended
   change.