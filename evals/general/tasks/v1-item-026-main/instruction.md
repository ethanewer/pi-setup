# Fix a CRLF / HTTP Header-Injection Vulnerability (CWE-93)

There is a small Bottle (Python) web service at `/app/main.py` exposing a
`GET /login` endpoint. The service builds a session `Set-Cookie` response
header from two **attacker-controlled** query parameters.

## Your task

1. **Trace the data flow** from the HTTP request to the response-header
   security boundary:
   - `user` and `role` query parameters (`request.query`)
   - → `build_session_cookie(user, role)`
   - → the `Set-Cookie` response header
   - → the raw HTTP response sent to the client.

   Identify where an attacker-controlled value can break out of the header
   line.

2. **Patch it with the smallest safe fix.** The weakness is that `user` /
   `role` are placed into an HTTP response header verbatim. A value such as
   `admin\r\nSet-Cookie: session=hijacked` (CRLF bytes) lets a client split
   the response and inject extra headers (CWE-93, HTTP response splitting).
   Apply the minimal fix so that:
   - `build_session_cookie` always returns a **single-line header value** with
     no CR or LF bytes (and otherwise keeps normal cookie semantics), and
   - the `/login` endpoint still works for ordinary users.

   Change as little as possible; do not rewrite the whole service or remove
   the endpoint.

3. **Run the regression test** and make it pass:
   ```
   python3 /app/regression_check.py
   ```
   It must print `REGRESSION OK`. It currently FAILS before your fix.
   You should also add at least one regression assertion of your own (either
   into `/app/regression_check.py` or a new file) that guards against
   CR/LF injection at this boundary, so the bug cannot regress later.

## Files
- `/app/main.py` — the service (edit the minimal amount needed to fix it).
- `/app/regression_check.py` — the regression test you are required to make
  pass (and extend if you like).

The grading checks that the security boundary is fixed: `build_session_cookie`
must never emit a CR or LF byte into the header value, normal requests still
return a valid single `Set-Cookie` header, and a crafted CRLF injection attempt
must not cause an injected header to appear.