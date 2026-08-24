# Harden a Multi-Layer Response-Splitting / CRLF Injection (CWE-93)

`/app` is a git repository holding a small Bottle (Python) HTTP service that
issues session cookies. There is an HTTP **response-splitting (CRLF) injection**
vulnerability (CWE-93): attacker-controlled input reaches the `Set-Cookie`
response header without newline sanitization, so a client can inject arbitrary
extra headers (for example `\r\nSet-Cookie: session=hijacked`).

Unlike a single-function lab, the data flows across **several modules**: a query
parameter is normalized, composed into a payload, and only then turned into the
response header value. You must trace the full path to the security boundary,
patch at the right place, and prove the fix with a regression test - without
changing the service contract.

## Requirements

1. **Trace the data flow to the security boundary.** Map, end to end:
   `token` query parameter → `service.keys.normalize` → `service.transport.compose`
   → `service.cookies.build` → the `Set-Cookie` response header emitted by the
   server. The CR/LF is dangerous *at the header boundary*; an intermediate
   transform alone will not stop the injection.

2. **Apply the smallest safe patch.** The boundary is `service.cookies.build()`.
   Harden it so the returned header value can never contain a CR or LF byte,
   regardless of input, while keeping ordinary cookie contents (e.g. `uid` /
   `ttl` values) intact. Do not remove the route, change its contract, or alter
   `main.py`'s request handling unless strictly necessary.

3. **Add a regression test.** Extend the shipped `tests/test_regression.py`
   (or add a new test file) with **at least one additional guard** beyond the
   ones provided - for example a fuzzed set of payloads containing raw `\r`,
   `\n`, and `\r\n` at various positions, asserting no newline ever appears in
   the header value.

4. **Run the full regression suite until green**:
   ```
   python3 -m pytest /app -q
   ```
   All tests (the shipped ones plus your addition) must pass.

5. **Commit via git.** Commit your source fix and the new test to the
   repository's git history with a clear, descriptive commit message. Leave the
   working tree clean (no uncommitted changes) at the end. Git history is part
   of the grading.

The verifier re-runs an independent copy of the regression suite against the
fixed service and checks that the repository has a committed fix with a clean
working tree.