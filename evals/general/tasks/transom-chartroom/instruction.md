# Trailing newlines in request headers are silently accepted

## Symptom (as a user would report it)

When a request is sent, header names and values that contain a return
character (`\r` or `\n`) anywhere in the name or value are supposed to be
rejected with `requests.exceptions.InvalidHeader`, because a value such as
`bar\nbaz: qux` can smuggle an extra header line into the request. That
rejection works for return characters *inside* a name or value, but a header
whose **name or value ends with a newline** — for example `{"foo": "bar\n"}`
or `{"foo\n": "bar"}` — is accepted and sent as if it were perfectly valid.
A header value that consists only of a newline is accepted too.

Desired behaviour: any header name or value containing a return character
(`\r` or `\n`) anywhere, **including at the very end**, must raise
`requests.exceptions.InvalidHeader`. Ordinary valid headers (plain names and
values, no leading whitespace, no return characters) must keep working
exactly as before.

## Environment

- `/app/src` is a `git` clone of the `requests` project, detached at a pinned
  commit. Its `src/requests` package is installed in **editable mode**, so
  edits you make under `/app/src/src/` are picked up immediately by
  `import requests`.
- Python 3.12. `pytest` 9.1.1, `pytest-httpbin` and `httpbin` are installed.
- The trial container has **no network**. Everything you need is already on
  disk; the project's own test files do not download anything for the tests
  listed below.
- `/opt/` and `/solution/` belong to the harness. Do not read or modify them.
- Do not modify anything outside `/app` — in particular, do not patch
  site-packages, `/usr`, `/opt` or Python's stdlib. The fix must be a source
  change inside the clone at `/app/src`. Keep the change as small as the bug
  allows; the checker assumes a minimal source diff and rejects unrelated
  modifications to the tree.

## What to do

### 1. Write a reproduction script (deliverable)

Create `/app/reproduce_header_newline_bug.py`, a standalone, deterministic
Python 3 script that demonstrates the bug and verifies the corrected
behaviour using the project's own public API:

- import `requests` as installed — do not manipulate `sys.path` and do not
  import by absolute path;
- via `requests.utils.check_header_validity` (the project's public header
  validity helper), require that **each** of the following header pairs
  raises `requests.exceptions.InvalidHeader`:
  - `("foo", "bar\n")` — value ends with a newline,
  - `("foo\n", "bar")` — name ends with a newline,
  - `("foo", "\n")` — value is a bare newline,
  - and the trailing `\r\n` variants `("foo", "bar\r\n")` and
    `("foo", "\r\n")`;
- also require that a plain valid header such as `("foo", "bar")` does **not**
  raise `InvalidHeader`;
- feel free to cover further trailing-newline variants of your own;
- exit `0` if and only if every check above holds (the corrected behaviour is
  present); exit non-zero, printing what failed to stderr, otherwise.

The script takes no command-line arguments, makes no network requests and
reads no files (other than importing the installed `requests`).

### 2. Fix the bug

Fix the underlying bug in the `requests` source inside `/app/src` so that
your reproduction passes and valid headers are still accepted. You will need
to work out where in the project the header validity decision is made.

### 3. Validate

From `/app/src`, run the project's own suite slice that covers this area and
confirm it stays green:

```
python3 -m pytest tests/test_utils.py tests/test_hooks.py tests/test_structures.py
```

An independent checker will additionally run the project's own regression
test for this bug and extra header inputs against your repaired tree, so fix
the behaviour, not the symptoms, and do not weaken validation of other header
shapes.

## Deliverables

- `/app/reproduce_header_newline_bug.py` — the reproduction script described
  above.
- `/app/src` — the repaired repository, with the bug fixed as a source
  change.