# Add retrying transports to HTTPX

## Environment

- HTTPX **0.28.1** is cloned at **`/app/src`** from the pinned upstream
  repository and installed **editable** into the Python environment, so any
  edit you make under `/app/src` is live the next time a process does
  `import httpx`.
- The container has **no network**. Every dependency you could need is
  already installed: `pytest`, `pytest-asyncio`, `anyio`, `trio`, `uvicorn`,
  `trustme`, `cryptography`, `chardet`, `h2`, `brotli`, `zstandard`. Do not
  try to `pip install` anything; it will fail.
- The machine is budgeted at one CPU. Everything here is pure Python, so
  pytest runs finish in seconds — there is no excuse for long test loops.

## The feature to build

HTTPX deliberately does **not** retry failed requests. A transient
connection drop or a `503 Service Unavailable` response is surfaced to the
caller on the first attempt, and there is no built-in way to make a request
survive a blip. This is a long-standing, documented gap in the project.

Your job: **add a retrying transport wrapper to the library itself**, in the
library's own idiom, that wraps any inner transport and re-issues the request
when an attempt fails transiently. It must be shipped as part of the `httpx`
package — not as a separate script — so that after your work is done, a fresh
interpreter can do:

```python
import httpx
with httpx.Client(transport=httpx.RetryTransport(...)) as client:
    ...
```

and the same for the async API (`httpx.AsyncRetryTransport` with
`httpx.AsyncClient`).

### Public contract (the feature spec)

Provide two new classes, importable at the package top level as
`httpx.RetryTransport` and `httpx.AsyncRetryTransport`. Both follow the
library's existing transport conventions:

- **Constructor** (keyword-only): `transport` — the inner transport to wrap
  (defaults to the standard network transport when omitted, so the wrapper is
  a drop-in replacement), and `max_attempts` (an integer >= 1, default 3; a
  value below 1 must be rejected with `ValueError`).
- `handle_request(request)` (sync) / `handle_async_request(request)` (async)
  — the same entry points the other transports implement (subtypes of
  `httpx.BaseTransport` / `httpx.AsyncBaseTransport`).
- `close()` (sync wrapper) / `aclose()` (async wrapper) — the release
  methods the other transports of each kind use — an `is_closed` property
  reporting whether the wrapper has been closed, and context-manager support
  matching the other transports' lifecycle.

**Retry semantics** (observable behaviour):

1. When an attempt raises an `httpx.TransportError` (connect, read, write,
   protocol or timeout errors), re-issue the request, up to `max_attempts`
   attempts. If every attempt fails, the caller sees the **last** error.
2. When an attempt returns a response with a retryable status — **429, 500,
   502, 503 or 504** — retry it, up to `max_attempts`. Any other response
   (2xx, 3xx, 4xx other than 429, 501, …) is returned as-is without a retry.
3. If a retryable response carries a `Retry-After` header that parses as a
   number of seconds, wait at least that long before the next attempt. With
   no (or an unparseable) `Retry-After`, the next attempt starts immediately.
4. When `max_attempts` is reached, the caller sees the real outcome: the last
   raised error, or the last response returned as-is (a response that is
   still retryable is still returned, not swallowed).
5. Connection hygiene: a response that is abandoned in favour of a retry
   must have its stream closed, so the underlying connection stack does not
   leak; the response the caller eventually receives must be fully readable
   through the client as normal.
6. The retries happen **inside the transport**: the same request object is
   replayed on each attempt with no client-level involvement, and the
   client's event hooks fire once per request, not once per attempt.

   The async wrapper must be backend-agnostic: the library's own async tests
   run under both asyncio and trio, and the acceptance's async checks do the
   same, so the async transport cannot depend on a specific event loop.
   (`anyio` is already a dependency of the project and solves exactly this.)

### How it must fit into the library

- Work through the package: after your change, `httpx.RetryTransport` and
  `httpx.AsyncRetryTransport` are importable from the installed `httpx`
  package in a fresh interpreter and usable as `transport=` for
  `httpx.Client` / `httpx.AsyncClient` exactly like `MockTransport` or
  `HTTPTransport`.
- Keep the library's own suite green for the parts your change touches. The
  acceptance runs these upstream test modules and they must all still pass:
  - `tests/client/test_event_hooks.py`
  - `tests/client/test_client.py`
  - `tests/test_exported_members.py`
  HTTPX asserts that every public attribute of the `httpx` module appears in
  `httpx.__all__`; when you add new public names, keep that invariant (add
  them to `__all__`) or the exported-members test fails.
- Do **not** change the signature of any existing public class or function.
  The acceptance re-asserts every existing public signature.
- Follow the project's own style — the transports subpackage, type comments,
  and conventions you'll find in the existing transports (e.g. `MockTransport`,
  `HTTPTransport`) are your guide. Where in the tree the implementation
  lives, what internal helpers it uses, and minor policy details (exact
  sleep/backoff for the no-`Retry-After` case) are **your design decision**.

## What you must deliver

1. The feature implemented inside the `/app/src` checkout (editable install),
   satisfying the contract above and keeping the three listed test modules
   green.
2. **`/app/feature.md`** — a short feature document (a few paragraphs, plus
   an example) that records:
   - the two class names and where the implementation is in `/app/src`;
   - the retry conditions, the `max_attempts` cap, and the `Retry-After`
     behaviour;
   - a working usage example wired into `httpx.Client` / `httpx.AsyncClient`;
   - the key design choices you made and how you verified the work
     (commands run, results).

Run the library's own tests on the three modules above yourself before
finishing; they are the acceptance bar for not breaking the existing
behaviour.

## Deliverable summary

- Code change under `/app/src` (the HTTPX checkout — required).
- `/app/feature.md` (required; see above).

A standalone script or a runtime monkeypatch is **not** a solution: the
acceptance imports `httpx` in fresh interpreters, so the feature must live in
the installed package's own source.