#!/bin/bash
#
# amber-guest oracle. Does the real work from a pristine container:
# authors the three protocol extension modules (multipart builder, chunked
# decoder, cookie store) and the extended request module under /app/httpkit/,
# then runs a self-check: imports all four deliverables, re-derives the
# visible /app/fixtures parses, and exercises edge cases of all three
# contracts. Never reads the hidden test directory.
set -euo pipefail

cat > /app/httpkit/multipart.py <<'PYEOF'
"""multipart/form-data body building (exact bytes).

Contract (task brief):

* ``make_boundary(seed)`` -> "----hkit" + 16 lowercase hex digits of
  seed & 0xFFFFFFFFFFFFFFFF;
* ``content_type(boundary)`` -> "multipart/form-data; boundary=" + boundary;
* ``multipart_encode(parts, boundary)`` -> exact multipart body bytes with
  CRLF line endings, documented quoting of names and filenames, and strict
  part ordering.

Values and file content are written verbatim (never escaped); an empty file
content_type omits the Content-Type header line.
"""


def make_boundary(seed):
    if not isinstance(seed, int):
        raise ValueError("seed must be an int")
    return "----hkit%016x" % (seed & 0xFFFFFFFFFFFFFFFF)


def content_type(boundary):
    return "multipart/form-data; boundary=" + boundary


def _check_boundary(boundary):
    if not isinstance(boundary, str):
        raise ValueError("boundary must be a str")
    if "\r" in boundary or "\n" in boundary:
        raise ValueError("boundary must not contain CR or LF")


def _esc(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def _check_quoted(text, what):
    if not isinstance(text, str):
        raise ValueError("%s must be a str" % what)
    if any((ord(c) < 0x20 or ord(c) == 0x7f) for c in text):
        raise ValueError("%s must not contain control characters" % what)


def _to_bytes(value):
    if isinstance(value, str):
        return value.encode("utf-8")
    if isinstance(value, bytes):
        return value
    raise ValueError("value/content must be str or bytes")


def multipart_encode(parts, boundary):
    """Encode a part list into exact multipart/form-data body bytes.

    parts is ordered; each entry is either:

    * ("field", name, value) or
    * ("file", name, filename, content_type, content).

    Any other shape raises ValueError.
    """
    _check_boundary(boundary)
    out = bytearray()
    for part in parts:
        if not isinstance(part, tuple):
            raise ValueError("each part must be a tuple")
        if len(part) == 3 and part[0] == "field":
            _, name, value = part
            _check_quoted(name, "name")
            if not name:
                raise ValueError("name must not be empty")
            out += ("--%s\r\n" % boundary).encode("ascii")
            out += ("Content-Disposition: form-data; name=\"%s\"\r\n"
                    % _esc(name)).encode("utf-8")
            out += b"\r\n"
            out += _to_bytes(value)
            out += b"\r\n"
        elif len(part) == 5 and part[0] == "file":
            _, name, filename, ctype, content = part
            _check_quoted(name, "name")
            _check_quoted(filename, "filename")
            if not name:
                raise ValueError("name must not be empty")
            if not isinstance(ctype, str):
                raise ValueError("content_type must be a str")
            out += ("--%s\r\n" % boundary).encode("ascii")
            out += ("Content-Disposition: form-data; name=\"%s\"; "
                    "filename=\"%s\"\r\n" % (_esc(name),
                                             _esc(filename))).encode("utf-8")
            if ctype:
                out += ("Content-Type: %s\r\n" % ctype).encode("utf-8")
            out += b"\r\n"
            out += _to_bytes(content)
            out += b"\r\n"
        else:
            raise ValueError("unknown part shape: %r" % (part,))
    out += ("--%s--\r\n" % boundary).encode("ascii")
    return bytes(out)
PYEOF

cat > /app/httpkit/chunked.py <<'PYEOF'
"""chunked transfer-encoding decoding with trailer surfacing.

Contract (task brief):

* size lines: hex size before the first ';' (case-insensitive, no 0x/+/space
  prefix); anything after ';' is a chunk extension and is ignored;
* chunks of size > 0 carry exactly `size` bytes then CRLF;
* after the final 0 chunk, an optional trailer section of `Name: value`
  lines (order preserved, duplicates allowed, values OWS-trimmed) ends with a
  required empty line;
* any leftover input, truncation, bad terminators, malformed sizes or
  trailers, and max_body overflow raise ChunkedError.

No network: pure bytes in, a ChunkedResult out.
"""


class ChunkedError(Exception):
    """Raised for any chunked-stream violation."""


class ChunkedResult:
    """Decoded chunked message: .body (bytes) and .trailers (list of
    (name, value) in wire order)."""

    def __init__(self, body, trailers):
        self.body = body
        self.trailers = trailers

    def __repr__(self):
        return "ChunkedResult(body=%r, trailers=%r)" % (self.body,
                                                        self.trailers)


_SIZECHARS = frozenset(b"0123456789abcdefABCDEF")
_TOKEN = frozenset(b"abcdefghijklmnopqrstuvwxyz"
                   b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~")


def _find_crlf(data, pos):
    idx = data.find(b"\r\n", pos)
    return idx if idx >= 0 else None


def decode_chunked(data, max_body=None):
    """Decode one complete chunked stream from ``data``.

    The entire input must be consumed; leftover bytes raise ChunkedError.
    """
    if not isinstance(data, bytes):
        raise ChunkedError("input must be bytes")
    pos = 0
    body_chunks = []
    trailers = []
    decoded_len = 0
    total = len(data)

    while True:
        line_end = _find_crlf(data, pos)
        if line_end is None:
            raise ChunkedError("bad chunk size")
        line = data[pos:line_end]
        pos = line_end + 2

        semi = line.find(b";")
        size_part = line if semi < 0 else line[:semi]
        if not size_part or any(c not in _SIZECHARS for c in size_part):
            raise ChunkedError("bad chunk size")
        size = int(size_part, 16)
        # extension bytes after ';' are ignored entirely.

        if size == 0:
            # final chunk: parse the trailer section.
            trailer_done = False
            while True:
                tline_end = _find_crlf(data, pos)
                if tline_end is None:
                    raise ChunkedError("unterminated trailers")
                tline = data[pos:tline_end]
                pos = tline_end + 2
                if tline == b"":
                    trailer_done = True
                    break
                colon = tline.find(b":")
                if colon <= 0:
                    raise ChunkedError("bad trailer")
                name_b = tline[:colon]
                if not name_b or any(c not in _TOKEN for c in name_b):
                    raise ChunkedError("bad trailer")
                value_b = tline[colon + 1:].strip(b" \t")
                trailers.append((name_b.decode("ascii"),
                                 value_b.decode("utf-8", "replace")))
            if not trailer_done:
                raise ChunkedError("unterminated trailers")
            break

        # data chunk
        if total - pos < size:
            raise ChunkedError("truncated chunk")
        if max_body is not None and decoded_len + size > max_body:
            raise ChunkedError("body too large")
        chunk_data = data[pos:pos + size]
        pos += size
        if data[pos:pos + 2] != b"\r\n":
            raise ChunkedError("chunk terminator")
        pos += 2
        body_chunks.append(chunk_data)
        decoded_len += size

    if pos != total:
        raise ChunkedError("trailing data")
    return ChunkedResult(b"".join(body_chunks), trailers)
PYEOF

cat > /app/httpkit/cookies.py <<'PYEOF'
"""Deterministic cookie store: parsing, scoping, eviction, assembly.

Contract (task brief): a documented attribute subset (Domain, Path,
Max-Age, Expires) of Set-Cookie lines is honored; domain-match and
path-match scoping, default-path computation, lazy expiry pruning,
identity-based replacement (created_at preserved), capacity eviction, and a
canonical Cookie header assembly order are all defined exactly; the clock
is injected so every behavior is deterministic.
"""

import email.utils
import re
import time
from urllib.parse import urlsplit

_TOKEN_RE = re.compile(r"[A-Za-z0-9!#$%&'*+\-.^_`|~]+\Z")
_INT_RE = re.compile(r"-?[0-9]+\Z")


def domain_match(host, domain):
    """RFC-style domain match: equal, or host is a subdomain of domain."""
    return host == domain or host.endswith("." + domain)


def path_match(request_path, cookie_path):
    """RFC-style path match: equal, or request path extends the cookie path
    right after a '/'."""
    if cookie_path == "/":
        return request_path.startswith("/")
    if request_path == cookie_path:
        return True
    return request_path.startswith(cookie_path + "/")


def default_path(url_path):
    """RFC 6265 5.1.4 default path for a URL path."""
    if not url_path or not url_path.startswith("/"):
        return "/"
    cut = url_path.rfind("/")
    if cut <= 0:
        return "/"
    return url_path[:cut]


class CookieStore:
    """A cookie jar with documented, deterministic rules."""

    def __init__(self, clock=None, max_cookies=100):
        if max_cookies is None or int(max_cookies) < 1:
            raise ValueError("max_cookies must be >= 1")
        self._clock = clock if clock is not None else time.time
        self._max = int(max_cookies)
        self._cookies = []

    # -- helpers -----------------------------------------------------------

    def _now(self):
        return float(self._clock())

    def _prune(self):
        now = self._now()
        self._cookies = [c for c in self._cookies
                         if c["expires"] is None or c["expires"] > now]

    def _identity_index(self, domain, path, name):
        for i, c in enumerate(self._cookies):
            if (c["domain"], c["path"], c["name"]) == (domain, path, name):
                return i
        return -1

    def _evict(self):
        while len(self._cookies) > self._max:
            keyed = [(c["expires"] if c["expires"] is not None
                      else float("inf"), c["created_at"], c["domain"],
                      c["path"], c["name"], c) for c in self._cookies]
            keyed.sort(key=lambda t: t[:5])
            self._cookies.remove(keyed[0][5])

    # -- public API --------------------------------------------------------

    def parse_set_cookie(self, line, request_url):
        """Parse one Set-Cookie line into a record dict, or None when the
        cookie must be rejected.  Records are dicts with keys name, value,
        domain, path, created_at, expires (int or None)."""
        if not isinstance(line, str):
            raise ValueError("Set-Cookie line must be a str")
        parsed = urlsplit(request_url)
        host = parsed.hostname
        if not host:
            raise ValueError("request_url has no host")
        host = host.lower()
        url_path = parsed.path or "/"

        segments = line.split(";")
        first = segments[0]
        if "=" not in first:
            return None
        name, _, raw_value = first.partition("=")
        if not _TOKEN_RE.fullmatch(name):
            return None
        value = raw_value.strip(" \t")

        domain = host
        cookie_path = default_path(url_path)
        max_age = None
        expires = None

        for seg in segments[1:]:
            attr, _, aval = seg.partition("=")
            aname = attr.strip(" \t").lower()
            aval = aval.strip(" \t")
            if aname == "domain":
                candidate = aval.lstrip(".").lower()
                if not candidate:
                    return None
                if "." not in candidate and candidate != "localhost":
                    return None
                if not domain_match(host, candidate):
                    return None
                domain = candidate
            elif aname == "path":
                if not aval.startswith("/"):
                    return None
                cookie_path = aval
            elif aname == "max-age":
                if not _INT_RE.fullmatch(aval):
                    return None
                max_age = int(aval)
            elif aname == "expires":
                try:
                    dt = email.utils.parsedate_to_datetime(aval)
                except (ValueError, TypeError):
                    dt = None
                if dt is None:
                    expires = None
                else:
                    expires = int(dt.timestamp())

        if max_age is not None:
            expires = self._now() + max_age

        return {"name": name, "value": value, "domain": domain,
                "path": cookie_path, "created_at": self._now(),
                "expires": expires}

    def store(self, line, request_url):
        """Parse and store one Set-Cookie.  Rejected cookies are no-ops;
        immediately-expired cookies remove any record with the same
        identity."""
        self._prune()
        record = self.parse_set_cookie(line, request_url)
        if record is None:
            return
        now = self._now()
        idx = self._identity_index(record["domain"], record["path"],
                                   record["name"])
        if record["expires"] is not None and record["expires"] <= now:
            if idx >= 0:
                del self._cookies[idx]
            return
        if idx >= 0:
            old = self._cookies[idx]
            old["value"] = record["value"]
            old["expires"] = record["expires"]
            # created_at is preserved on overwrite.
        else:
            self._cookies.append(record)
        self._evict()

    def set_cookies(self, headers, request_url):
        """Store every Set-Cookie header from an (name, value) header list."""
        for name, value in headers:
            if str(name).lower() == "set-cookie":
                self.store(value, request_url)

    def _applicable(self, request_url):
        self._prune()
        parsed = urlsplit(request_url)
        host = parsed.hostname
        if not host:
            raise ValueError("request_url has no host")
        host = host.lower()
        url_path = parsed.path or "/"
        out = []
        for c in self._cookies:
            if domain_match(host, c["domain"]) and path_match(url_path,
                                                              c["path"]):
                if c["expires"] is None or c["expires"] > self._now():
                    out.append(c)
        out.sort(key=lambda c: (-len(c["path"]), c["name"], c["domain"],
                                c["created_at"]))
        return out

    def request_cookies(self, request_url):
        """Cookies applying to the URL, in Cookie-header assembly order, as
        dicts with exactly name, value, domain, path."""
        return [{"name": c["name"], "value": c["value"],
                 "domain": c["domain"], "path": c["path"]}
                for c in self._applicable(request_url)]

    def cookie_header(self, request_url):
        """The Cookie: header value, or '' when no cookie applies."""
        parts = ["%s=%s" % (c["name"], c["value"])
                 for c in self._applicable(request_url)]
        return "; ".join(parts)

    def snapshot(self):
        """All live records as dicts (name, value, domain, path, created_at,
        expires), sorted by (domain, path, name)."""
        self._prune()
        out = [dict(c) for c in self._cookies]
        out.sort(key=lambda c: (c["domain"], c["path"], c["name"]))
        return out

    def clear(self):
        self._cookies = []
PYEOF

cat > /app/httpkit/request.py <<'PYEOF'
"""httpkit.request - request building and response parsing (extended).

Extends the shipped base edition per the task contract:

* ``build_request`` accepts an optional request ``body`` and appends a
  Content-Length header when none was supplied;
* ``parse_response`` decodes chunked transfer-encoding bodies (via
  ``httpkit.chunked``), surfacing trailers, and raises ValueError on framing
  or chunked-stream violations.

Everything here is pure bytes in / bytes out; no network I/O happens
anywhere in the library.
"""

import re

from . import chunked as _chunked

_STATUS_RE = re.compile(r"^HTTP/1\.[01] ([0-9]{3})(?: (.*))?$")


class Response(tuple):
    """Parsed HTTP response: (status, reason, headers, body, trailers).

    headers is a list of (name, value) pairs as they appeared on the wire
    (name case preserved, value OWS-trimmed).  trailers is a list of
    (name, value) pairs for chunked bodies, else empty.
    """

    __slots__ = ()

    def __new__(cls, status, reason, headers, body, trailers):
        return tuple.__new__(cls, (status, reason, list(headers),
                                   body, list(trailers)))

    @property
    def status(self):
        return self[0]

    @property
    def reason(self):
        return self[1]

    @property
    def headers(self):
        return self[2]

    @property
    def body(self):
        return self[3]

    @property
    def trailers(self):
        return self[4]

    def header(self, name):
        low = name.lower()
        for n, v in self.headers:
            if n.lower() == low:
                return v
        return None


def _check_header_line(name, value):
    if not isinstance(name, str) or not isinstance(value, str):
        raise ValueError("header name and value must be str")
    if "\r" in name or "\n" in name or "\r" in value or "\n" in value:
        raise ValueError("header name/value must not contain CR or LF")
    if not name:
        raise ValueError("header name must not be empty")


def build_request(method, path, headers=None, body=None):
    """Build one HTTP/1.1 request as bytes.

    method must be ASCII letters; path must start with '/' and contain no CR
    or LF.  headers is an ordered sequence of (name, value) pairs (or a dict,
    insertion order).  When body (bytes) is given and no Content-Length header
    appears among the supplied header names (case-insensitive), a
    Content-Length header is appended after the supplied ones; a supplied
    Content-Length must equal len(body).  The request ends CRLF CRLF before
    the body.
    """
    if not re.fullmatch(r"[A-Za-z]+", method):
        raise ValueError("method must be ASCII letters")
    if not isinstance(path, str) or not path.startswith("/"):
        raise ValueError("path must be a non-empty string starting with '/'")
    if "\r" in path or "\n" in path:
        raise ValueError("path must not contain CR or LF")

    if isinstance(headers, dict):
        header_items = list(headers.items())
    else:
        header_items = list(headers or [])

    if body is not None and not isinstance(body, bytes):
        raise ValueError("body must be bytes")

    lines = ["%s %s HTTP/1.1" % (method, path)]
    found_cl = False
    for name, value in header_items:
        _check_header_line(name, value)
        lines.append("%s: %s" % (name, value))
        if name.lower() == "content-length":
            found_cl = True
    if body is not None:
        if found_cl:
            for name, value in header_items:
                if name.lower() == "content-length":
                    if str(value).strip() != str(len(body)):
                        raise ValueError(
                            "Content-Length does not match body length")
                    break
        else:
            lines.append("Content-Length: %d" % len(body))
    head = ("\r\n".join(lines) + "\r\n\r\n").encode("ascii")
    return head + (body or b"")


def parse_response(data):
    """Parse a full HTTP response from bytes.

    Framing, in order: a Transfer-Encoding header containing "chunked"
    switches to chunked decoding (httpkit.chunked.decode_chunked, full
    consumption; a ChunkedError surfaces as ValueError with the same
    message); a non-chunked Transfer-Encoding is unsupported; otherwise
    Content-Length frames the body exactly; with neither header the body
    must be empty.
    """
    if not isinstance(data, bytes):
        raise ValueError("data must be bytes")
    sep = data.find(b"\r\n\r\n")
    if sep < 0:
        raise ValueError("no header terminator")
    head, rest = data[:sep], data[sep + 4:]

    lines = head.split(b"\r\n")
    m = _STATUS_RE.match(lines[0].decode("ascii", "replace"))
    if not m:
        raise ValueError("bad status line")
    status = int(m.group(1))
    reason = m.group(2) or ""

    headers = []
    for line in lines[1:]:
        text = line.decode("ascii", "replace")
        if text[:1] in (" ", "\t"):
            raise ValueError("folded header")
        if ":" not in text:
            raise ValueError("header without colon")
        name, _, value = text.partition(":")
        if not name:
            raise ValueError("empty header name")
        headers.append((name, value.strip(" \t")))

    low = {}
    for n, v in headers:
        low.setdefault(n.lower(), v)
    te = low.get("transfer-encoding")
    if te is not None:
        if "chunked" not in te.lower():
            raise ValueError("unsupported transfer-encoding")
        try:
            result = _chunked.decode_chunked(rest)
        except _chunked.ChunkedError as exc:
            raise ValueError(str(exc))
        return Response(status, reason, headers, result.body,
                        result.trailers)
    cl = low.get("content-length")
    if cl is not None:
        if not re.fullmatch(r"[0-9]+", cl.strip()):
            raise ValueError("bad content-length")
        want = int(cl.strip())
        if len(rest) < want:
            raise ValueError("truncated body")
        if len(rest) > want:
            raise ValueError("extra bytes after body")
        return Response(status, reason, headers, rest[:want], [])
    if rest:
        raise ValueError("unframed body")
    return Response(status, reason, headers, b"", [])
PYEOF

# ---------------------------------------------------------------------------
# Self-check: the oracle must not leave a broken library behind.  This
# re-derives the visible fixture parses and exercises contract edge cases.
# ---------------------------------------------------------------------------
cd /app && python3 - <<'PYEOF'
import base64, json, os, sys

sys.path.insert(0, "/app")
import httpkit.multipart as mp
import httpkit.chunked as ch
import httpkit.cookies as ck
import httpkit.request as rq

FI = "/app/fixtures"
exp = json.load(open(os.path.join(FI, "expected_parses.json")))

# visible fixtures re-derived
req = rq.build_request("GET", "/health",
                       [("Host", "fixture.test"), ("Accept", "*/*")])
assert req == open(os.path.join(FI, "request_get.bin"), "rb").read()

parts = [("field", "username", "kestrel_fan"),
         ("field", "comment", "hello \u00fcn\u00efcode \u2603"),
         ("file", "avatar", "head shot.png", "image/png",
          b"\x89PNG\r\n\x1a\n"),
         ("field", "empty", ""),
         ("file", "manifest", "m.txt", "", "hello manifest")]
b = mp.make_boundary(1)
body = mp.multipart_encode(parts, b)
assert b == "----hkit0000000000000001"
assert body == base64.b64decode(exp["request_multipart.bin"]
                                ["request"]["body_b64"])
blob = rq.build_request("POST", "/upload",
                        [("Host", "fixture.test"),
                         ("Content-Type", mp.content_type(b))], body=body)
assert blob == open(os.path.join(FI, "request_multipart.bin"), "rb").read()

simple = rq.parse_response(
    open(os.path.join(FI, "response_simple.txt"), "rb").read())
assert simple.status == 200 and simple.body == b'{"ok": true}'
chunked = rq.parse_response(
    open(os.path.join(FI, "response_chunked.bin"), "rb").read())
assert chunked.body == b"hello world"
assert chunked.trailers == [("X-Trailer", "first"), ("X-Trailer", "second")]

# multipart edge: quoting + empty content-type + bad shapes
assert mp.multipart_encode(
    [("field", 'a"b\\c', "v")], "bm") == (
    b"--bm\r\nContent-Disposition: form-data; "
    b'name="a\\"b\\\\c"\r\n\r\nv\r\n--bm--\r\n')
try:
    mp.multipart_encode([("field", "", "v")], "b")
    raise SystemExit("empty name accepted")
except ValueError:
    pass
try:
    mp.multipart_encode([("x",)], "b")
    raise SystemExit("bad shape accepted")
except ValueError:
    pass

# chunked edge: trailers, extensions, malformed streams
assert ch.decode_chunked(
    b"A\r\n0123456789\r\n2;foo=\"a;b\"\r\nhi\r\n0\r\nT: v\r\n\r\n"
).body == b"0123456789hi"
for bad in (b"0\r\n", b"5\r\nhi\r\n", b"1\r\nx\r\n0\r\n\r\njunk", b"ZZ\r\n",
            b"+5\r\nhi\r\n0\r\n\r\n", b"5 \r\nhi\r\n0\r\n\r\n",
            b"3\r\nabc\n\r\n0\r\n\r\n", b"0\r\n bad: v\r\n\r\n"):
    try:
        ch.decode_chunked(bad)
        raise SystemExit("malformed stream accepted: %r" % bad)
    except ch.ChunkedError:
        pass
try:
    ch.decode_chunked(b"9\r\n0123456789\r\n0\r\n\r\n", max_body=5)
    raise SystemExit("max_body ignored")
except ch.ChunkedError:
    pass

# cookie edge: injected clock, scoping, overwrite, eviction, ordering
clock = [1000.0]
jar = ck.CookieStore(clock=lambda: clock[0], max_cookies=3)
jar.store("a=1", "http://example.com/deep/path")
assert jar.snapshot()[0]["path"] == "/deep", jar.snapshot()
jar.store("b=2; Path=/", "http://example.com/")
assert jar.cookie_header("http://example.com/deep/path/x") == "a=1; b=2"
jar.store("u=top; Domain=example.com", "http://sub.example.com/")
assert jar.cookie_header("http://sub.example.com/x") == "b=2; u=top"
jar.clear()
jar.store("t=1; Max-Age=10", "http://example.com/")
clock[0] = 1011.0
jar.store("k=2", "http://example.com/")
assert "t=1" not in jar.cookie_header("http://example.com/")
jar.clear()
clock[0] = 1000.0
for i in range(4):
    clock[0] = 1000.0 + i
    jar.store("c%d=1" % i, "http://example.com/")
assert len(jar.snapshot()) == 3
assert all(c["name"] != "c0" for c in jar.snapshot())

print("amber-guest oracle self-check passed")
PYEOF

/usr/bin/env python3 -c "import sys; sys.path.insert(0,'/app'); import httpkit.multipart, httpkit.chunked, httpkit.cookies, httpkit.request; print('deliverables importable')"

echo "amber-guest oracle complete"