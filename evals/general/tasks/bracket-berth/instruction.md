# Bracket-berth: an HTTP client that chokes on an empty zstd-encoded body

## The bug you must fix

The `httpx` library installed in this container misbehaves on a specific,
realistic HTTP response shape.

Some servers answer a request with a zero-length response body while still
advertising `Content-Encoding: zstd` on the response headers. That is legal:
there is simply nothing to decompress, so the body must read back as empty
bytes. It is not a truncated or damaged stream. Instead of returning the
empty body, this library raises an unexpected error the moment the body is
read, complaining that the compressed data is incomplete. Every code path
that materialises the body is affected — reading `response.content`,
iterating `response.iter_bytes()`, or a plain `response.read()` — so any
client that talks to such an endpoint crashes on the body instead of getting
its empty result.

You can reproduce it right now with the installed package (no network
needed; the response is constructed in memory):

```
python3 -c "import httpx; r = httpx.Response(200, headers=[(b'Content-Encoding', b'zstd')], content=b''); print(repr(r.content))"
```

Today it exits non-zero with an `httpx.DecodingError` instead of printing
`b''`. Your job is to make the library behave correctly.

## Environment

- `/app/src` is a real, SHA-pinned source checkout of httpx (a shallow git
  clone, checked out on the revision the image was built with — leave it on
  that revision; do not create git commits or move the checkout).
- The library is editable-installed from that checkout: any edit you make to
  the Python source under `/app/src/httpx/` is live in `import httpx`
  immediately, in every fresh interpreter.
- The `zstandard` package (0.25.0) is installed, which is what enables httpx
  to decode `zstd`-encoded responses. Also installed: the project's test
  toolchain (pytest, brotli, chardet, anyio, trio, uvicorn, trustme,
  cryptography, h2). See `/app/README.md`.
- There is no network in this container. Do not attempt to install packages
  or fetch anything. Everything you need is already on disk.
- Do not modify anything under `/app/src` other than the httpx library
  source that your fix actually requires, and do not add any new files to
  the checkout — the grader verifies that the upstream working tree is
  otherwise untouched.

## Deliverable

The fix must live in the httpx source tree at `/app/src` — it has to be a
real repair of the library, not a workaround in a script or a wrapper.
Satisfy all of the following:

1. The reproducer above must print `b''` and exit 0.
2. Reading the body must not raise for any zero-length zstd-encoded
   response: `.content`, `.read()`, `.iter_bytes()` on a `Response` with an
   empty zstd body, and responses that arrive through a real
   `httpx.Client`/`httpx.AsyncClient` round-trip (for example against a
   `httpx.MockTransport`) must all return/…-iterate an empty byte string.
3. The library's existing decoder behaviour must stay intact: non-empty
   zstd bodies must still decode, and *truncated* zstd streams must still
   raise `httpx.DecodingError`. The project's own decoder tests must stay
   green:
   ```
   cd /app/src && python3 -m pytest -q -p no:cacheprovider tests/test_decoders.py
   ```
4. Write a short report at `/app/fix-report.md` (plain text or Markdown,
   at least a few sentences) that a maintainer could act on. It must state
   precisely where the fault lives — the module and the decoding step that
   wrongly treats "no data at all" as "incomplete data" — naming that file
   by its full path under `/app/src/httpx/`, the minimal change you made,
   and how you verified it.

The grader checks the fixed tree directly (it runs the project's own
regression tests against your checkout, plus additional hidden cases on the
same code path), so make the fix in the source and leave it on disk.

## Notes

- `cpus = 1`; keep any invocations sequential.
- Debugging hint: the failure is about the difference between an *empty*
  body and a *truncated* one. The project distinguishes these two cases
  elsewhere in the same machinery — look at how a sibling decoder handles
  "no data has ever been fed" before deciding where the fault is.
- When you think you are done, run the reproducer, run the test command in
  requirement 3, and briefly exercise the async reading paths too.