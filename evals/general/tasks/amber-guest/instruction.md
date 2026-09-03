# Amber Guest — HTTP client protocol internals for `httpkit`

`/app/httpkit` is a small self-authored HTTP client library written in pure
Python. It **builds requests as bytes** and **parses response bytes** — there
is no network anywhere; everything operates on byte fixtures and plain
values. The current edition only supports simple requests (no request body)
and Content-Length-framed responses. Your job: implement three documented
protocol contracts and wire them into the library.

## Files

Shipped (do not modify):

- `/app/httpkit/__init__.py` — package init; keep it as shipped.
- `/app/httpkit/request.py` — the request builder / response parser, base
  edition. **This is a deliverable you must extend** (see contract below).
- `/app/fixtures/` — visible byte fixtures + `/app/fixtures/expected_parses.json`
  describing how each fixture parses (sanity material; do not modify).

Your deliverables (you create/extend all four):

1. `/app/httpkit/multipart.py` — multipart/form-data body builder.
2. `/app/httpkit/chunked.py` — chunked transfer-encoding decoder.
3. `/app/httpkit/cookies.py` — deterministic cookie store.
4. `/app/httpkit/request.py` — extended per contract 4.

Constraints: Python 3.12 **standard library only** (use `urllib.parse`,
`email.utils`, `datetime` where needed); no third-party packages, no network
access, no reading `/tests`. Everything must be deterministic: fixed
algorithms, no wall-clock randomness — the cookie store takes its clock as a
constructor parameter.

---

## 1. Contract — `/app/httpkit/multipart.py`

```python
def make_boundary(seed: int) -> str
def content_type(boundary: str) -> str
def multipart_encode(parts: list, boundary: str) -> bytes
```

- `make_boundary(seed)`: `"----hkit"` + 16 lowercase hex digits of
  `seed & 0xFFFFFFFFFFFFFFFF`. (Used by fixtures; tests pass explicit
  boundaries too.)
- `content_type(boundary)`: exactly `"multipart/form-data; boundary=" + boundary`
  (boundary emitted unquoted).
- `multipart_encode(parts, boundary)`: exact body bytes (UTF-8 for str
  values, CRLF line endings everywhere).

**Part shapes** (each is a tuple; any other shape raises `ValueError`):

- `("field", name, value)` — value is `str` or `bytes`.
- `("file", name, filename, content_type, content)` — filename/`content_type`
  are `str` (may be empty), content is `str` or `bytes`.

**Emission rules** (byte-exact):

- Field part:
  ```
  --<boundary>\r\n
  Content-Disposition: form-data; name="<name>"\r\n
  \r\n
  <value>\r\n
  ```
- File part (adds `filename` and, when `content_type` is non-empty, a
  `Content-Type` line):
  ```
  --<boundary>\r\n
  Content-Disposition: form-data; name="<name>"; filename="<filename>"\r\n
  Content-Type: <content_type>\r\n
  \r\n
  <content>\r\n
  ```
  An empty `content_type` **omits** the `Content-Type` line entirely.
- Parts are emitted **exactly in list order**; after the last part, the
  closing delimiter `--<boundary>--\r\n` terminates the body.
- `name` must be a non-empty `str`; `name`/`filename` must not contain
  control characters (ord < 0x20 or == 0x7f) — else `ValueError`.
- In `name`/`filename`, a backslash is written as `\\` and a double quote as
  `\"`. All header lines (Disposition, filename, Content-Type) are emitted
  UTF-8-encoded; values/content are written **verbatim** as bytes (str values
  UTF-8-encoded; never escaped, never boundary-checked).
- `boundary` must be a `str` without CR/LF (else `ValueError`); it encodes
  as ASCII. Recommended charset: RFC-style boundary chars; use
  `make_boundary` output or `[A-Za-z0-9'()+_,-./:=?-]`-only strings in tests.

## 2. Contract — `/app/httpkit/chunked.py`

```python
class ChunkedError(Exception): ...
class ChunkedResult:            # exposes .body (bytes) and .trailers (list)
def decode_chunked(data: bytes, max_body: int | None = None) -> ChunkedResult
```

Wire grammar (RFC-style): `chunk = size-line CRLF data CRLF`; the final chunk
has size `0`; afterwards an optional **trailer section** (header-field lines
followed by an empty line) ends the message. `decode_chunked` must consume
the whole input or raise. The input `data` is always `bytes`; passing any
other type (e.g. a `str`) raises `ChunkedError`.

- Each size line ends with CRLF. The size is the part before the first `;`
  (case-insensitive hex, one or more of `[0-9a-fA-F]`, no `0x`/`+` prefix, no
  whitespace) — anything else raises `ChunkedError("bad chunk size")`. The
  rest of the line after `;` is a **chunk extension and is ignored**.
- Chunks with size > 0: exactly `size` bytes of data must follow, then CRLF.
  Fewer bytes available → `ChunkedError("truncated chunk")`; data not
  followed by CRLF (or data ends early) → `ChunkedError("chunk terminator")`.
- After the final chunk (size `0`, extensions allowed): zero or more trailer
  lines `Name: value`, each ending CRLF, then a required empty line. Trailer
  names must be non-empty strings of token characters — exactly the
  `[A-Za-z0-9!#$%&'*+\-.^_`|~]+` set used for cookie names, so whitespace,
  `:`, `;`, `=`, `@` etc. are all invalid — otherwise
  `ChunkedError("bad trailer")`. Values are trimmed of leading/trailing
  spaces and tabs. Duplicate names are allowed and must be surfaced **in wire
  order**. A missing empty line → `ChunkedError("unterminated trailers")`.
- No trailers: the message ends with `0\r\n\r\n`.
- Any bytes remaining after the terminating empty line →
  `ChunkedError("trailing data")`.
- `max_body` (when not `None`, `>= 0`): if accepting a chunk would push the
  decoded body past the limit → `ChunkedError("body too large")`.
- `ChunkedResult` exposes `.body` (the concatenated chunk data) and
  `.trailers` (list of `(name, value)` in wire order).

## 3. Contract — `/app/httpkit/cookies.py`

```python
class CookieStore:
    def __init__(self, clock=None, max_cookies=100)
    def parse_set_cookie(self, line: str, request_url: str) -> dict | None
    def store(self, line: str, request_url: str) -> None
    def set_cookies(self, headers: list, request_url: str) -> None
    def cookie_header(self, request_url: str) -> str
    def request_cookies(self, request_url: str) -> list
    def snapshot(self) -> list
    def clear(self) -> None
```

- `clock` is a callable returning epoch seconds (float/int) — your tests
  inject a fake clock; default is `time.time`. `max_cookies` caps stored
  cookies (after this the documented eviction applies); must be `>= 1`.
- `request_url` is any URL string; the store uses `urllib.parse.urlsplit`:
  `host = parsed.hostname` (always present — missing host raises
  `ValueError`), `path = parsed.path or "/"`. Query/fragment/userinfo/port are
  ignored for scoping.
- `headers` for `set_cookies` is a list of `(name, value)` pairs (e.g. the
  `headers` list from a parsed response); every header whose name is
  `Set-Cookie` (case-insensitive) is stored.

**Parsing a Set-Cookie line.** Split on `;`. The first segment is the
cookie-pair: `name=value`. `name` must be a non-empty token matching
`[A-Za-z0-9!#$%&'*+\-.^_`|~]+`, with no leading whitespace — otherwise the
cookie is rejected (parse returns `None`, store is a no-op). Split at the
**first** `=`: no `=` → rejected. `value` is everything after the first `=`
(empty allowed), trimmed of leading/trailing spaces and tabs; may contain
`=`.

Remaining segments are attributes (split at first `=`, attribute name
case-insensitive, value trimmed of spaces/tabs; a segment without `=` gets
value `""`). Only these are honored; all others (`Secure`, `HttpOnly`,
`SameSite`, anything else) are ignored:

- `Domain`: strip any leading `.`s, lowercase. Reject the cookie if the
  result is empty, or contains no `.` and is not `localhost`, or does not
  **domain-match** the request host. Domain-match: `host == domain` or
  `host.endswith("." + domain)`. Absent → default domain is the request host.
- `Path`: if present it must start with `/`, else the cookie is rejected.
  Absent → **default path**: take the URL path, cut off everything from the
  right-most `/` (inclusive); if the result is empty, `/`. So `/a/b/c` →
  `/a/b`; `/a/b/` → `/a/b`; `/a` → `/`; `/` → `/`.
- `Max-Age`: the value must match `-?[0-9]+`, else the cookie is rejected.
  `<= 0` → the cookie is immediately expired (see below). Present `Max-Age`
  wins over `Expires`.
- `Expires`: only consulted when `Max-Age` is absent. Parse with
  `email.utils.parsedate_to_datetime(str(value))`; an unparseable value makes
  the cookie a **session cookie** (no expiry, `expires=None`). Otherwise
  `expires = int(ts.timestamp())`.

**Cookie record.** `{"name", "value", "domain", "path", "created_at",
"expires"}` — `domain` lowercased, `path` as decided above, `created_at =
clock()` at creation, `expires` an int or `None`.

**Store behavior.**

- Expired cookies (a record whose `expires` is not `None` and `<= now`) are
  pruned lazily at the start of `parse`, `store`, `cookie_header`,
  `request_cookies` and `snapshot`.
- `store`: if the parsed cookie has `expires <= now` at store time, or
  `Max-Age <= 0`, it is treated as expired: any existing cookie with the same
  identity is removed and nothing new is stored.
- Identity = exact `(domain, path, name)`. Storing a cookie whose identity
  already exists **replaces** value/expires, and **keeps the original
  `created_at`**. Otherwise a new record is appended (created_at = now).
- After storing, while `len > max_cookies`, evict the record that sorts
  **first** under key `(expires if expires is not None else float("inf"),
  created_at, domain, path, name)` (ascending), until the count fits.

**Reading.**

- `request_cookies(url)`: the cookies that apply to `url`: domain-match the
  host, **path-match** the path (`req == cpath`, or `cpath == "/"` with
  `req` starting with `/`, or `req.startswith(cpath + "/")`), and not
  expired. Sorted by `(-len(path), name, domain,
  created_at)` (ascending on the latter three). Each item is a dict with
  exactly `name`, `value`, `domain`, `path`.
- `cookie_header(url)`: the same cookies, formatted `name=value` joined with
  `"; "`, in that sort order. Empty string when none apply.
- `snapshot()`: prunes first, then returns all live records as dicts with
  exactly the keys above, sorted by `(domain, path, name)`.
- `clear()`: remove every stored cookie.

## 4. Contract — `/app/httpkit/request.py` (extended)

Keep a `Response` type exposing `.status` (int), `.reason` (str),
`.headers` (list of `(name, value)` preserving wire order and case),
`.body` (bytes), `.trailers` (list of `(name, value)`); plus `header(name)`
returning the first case-insensitively matching value or `None`.

- `build_request(method, path, headers=None, body=None) -> bytes` — as in the
  base edition, plus: `body` (bytes, optional). When `body` is given and no
  `Content-Length` appears among the supplied header names
  (case-insensitive), a `Content-Length: <len>` header is appended after the
  supplied ones. A supplied `Content-Length` must equal `len(body)` (else
  `ValueError`). The request ends CRLF CRLF then the body bytes.
- `parse_response(data) -> Response` — as in the base edition, plus:

  - A `Transfer-Encoding` header whose value contains `chunked`: decode the
    remainder with `httpkit.chunked.decode_chunked`, return its body and
    trailers (full consumption enforced; a `ChunkedError` should surface as
    `ValueError` with the same message).
  - A `Transfer-Encoding` that is present but not chunked →
    `ValueError("unsupported transfer-encoding")`.
  - Otherwise Content-Length framing and the unframed-body error behave
    exactly as the base edition documents.

The typical multipart flow:

```python
import httpkit.multipart, httpkit.request
parts = [("field", "username", "kestrel_fan"),
         ("file", "avatar", "a.png", "image/png", b"...")]
b = httpkit.multipart.make_boundary(1)
body = httpkit.multipart.multipart_encode(parts, b)
req = httpkit.request.build_request(
    "POST", "/upload",
    [("Host", "fixture.test"),
     ("Content-Type", httpkit.multipart.content_type(b))],
    body=body)
```

## How the grader probes it

Hidden probes hold byte fixtures and scripted exchanges you have not seen and
re-derive everything from the rules above with **independent reference
implementations**: exact produced bytes (multipart), decoded structures
(chunked, including trailer ordering and every malformed-case error),
and cookie-store states/headers across scripted exchanges (scope conflicts,
evictions, ordering). The probes also re-run the visible
`/app/fixtures/` files through your code and compare to independently
recomputed parses. A hardcoded visible output fails the hidden cases. Keep
the rule text above as your single source of truth — every edge case listed
is exercised.