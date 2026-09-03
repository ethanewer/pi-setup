# amber-guest — HTTP client protocol internals.
#
# Ships a self-authored mini HTTP client library /app/httpkit/ that builds
# requests as bytes and parses response bytes, but only supports simple GET
# with Content-Length.  The agent must extend the library with three
# documented protocol pieces: a multipart/form-data body builder
# (/app/httpkit/multipart.py), a chunked transfer-encoding decoder
# (/app/httpkit/chunked.py), and a deterministic cookie store
# (/app/httpkit/cookies.py), and upgrade /app/httpkit/request.py so the
# request builder takes a body and the response parser decodes chunked
# bodies.  Visible byte fixtures live in /app/fixtures/ with documented
# expected parses; hidden probes re-encode/decoding everything independently.
FROM bench-base:python-3.12

WORKDIR /app

COPY files/httpkit/ /app/httpkit/
COPY files/fixtures/ /app/fixtures/

# Pristine copies used by the verifier to detect content tampering of
# shipped, do-not-modify files (package init and the visible fixtures).
COPY files/httpkit/__init__.py /opt/pristine/httpkit__init__.py
COPY files/fixtures/ /opt/pristine/fixtures/

# Sanity: the shipped core alone works for simple GET + Content-Length and
# explicitly refuses chunked responses until the agent extends it.
RUN python3 - <<'PY'
import sys
sys.path.insert(0, "/app")
import httpkit.request as r
req = r.build_request("GET", "/health", [("Host", "fixture.test")])
assert req == b"GET /health HTTP/1.1\r\nHost: fixture.test\r\n\r\n", req
resp = r.parse_response(
    b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
assert (resp.status, resp.body) == (200, b"ok"), resp
try:
    r.parse_response(
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
    raise SystemExit("base parser must not support chunked yet")
except ValueError as exc:
    assert "chunked" in str(exc)
print("httpkit base sanity ok")
PY