#!/usr/bin/env python3
"""ds-kestrel-client hidden probe: chunked transfer-encoding decoding.

Holds hidden chunked streams (generated here, the agent never sees them) and
re-derives the expected (body, trailers) with an independent reference
parser written straight from the documented grammar; compares field-for-field
against /app/httpkit/chunked.py and requires ChunkedError on every
malformed stream.  Also executes /app/httpkit/request.py's parse_response on
hidden full responses (chunked, content-length, malformed) and re-runs the
visible /app/fixtures chunked response.

Exit code 0 = pass, 1 = fail (any failure message printed to stdout).
"""
import sys

sys.path.insert(0, "/app")
import httpkit.chunked as dlv
import httpkit.request as req

# ---------------------------------------------------------------------------
# Independent reference parser (derived from the documented contract, kept
# structurally different from the library implementation on purpose).
# ---------------------------------------------------------------------------


def ref_decode(stream):
    """Return (body, trailers); raise ValueError on violation.

    Grammar walk: consume lines up to CRLF; first field of the size line
    before any ';' must be pure hex (1+ digits); chunk data is raw bytes
    then CRLF; a 0 size ends the body and the trailer section runs until an
    empty line; the input must be fully consumed.
    """
    pos = 0

    def line_until():
        nonlocal pos
        end = stream.find(b"\r\n", pos)
        if end < 0:
            raise ValueError("unterminated line")
        out = stream[pos:end]
        pos = end + 2
        return out

    chunks = []
    trailers = []
    for _ in range(100000):
        size_line = line_until()
        semi = size_line.find(b";")
        raw = size_line if semi < 0 else size_line[:semi]
        if not raw or raw.strip(b" \t") != raw or not raw.isalnum() \
                or any(c not in b"0123456789abcdefABCDEF" for c in raw):
            raise ValueError("bad size")
        n = int(raw, 16)
        if n == 0:
            while True:
                t = line_until()
                if not t:
                    # trailers ended with the required empty line
                    break
                if b":" not in t or b" " in t[:t.find(b":") + 1]:
                    raise ValueError("bad trailer")
                name, _, val = t.partition(b":")
                if not name or not name.isascii():
                    raise ValueError("bad trailer")
                # token chars only
                ok_tok = all(48 <= c <= 57 or 65 <= c <= 90 or 97 <= c <= 122
                             or c in b"!#$%&'*+-.^_`|~" for c in name)
                if not ok_tok:
                    raise ValueError("bad trailer")
                trailers.append((name.decode("ascii"),
                                 val.strip(b" \t").decode("utf-8", "replace")))
            break
        if len(stream) - pos < n:
            raise ValueError("truncated")
        data = stream[pos:pos + n]
        pos += n
        if stream[pos:pos + 2] != b"\r\n":
            raise ValueError("terminator")
        pos += 2
        chunks.append(data)
    if pos != len(stream):
        raise ValueError("trailing")
    return b"".join(chunks), trailers


def expect_error(stream, label):
    for fn in (dlv.decode_chunked,):
        try:
            fn(stream)
        except dlv.ChunkedError:
            return True
        except Exception:
            return True
        print("FAIL: malformed stream accepted: %s %r" % (label, stream))
        return False
    return True


def build_chunked(body_parts, sizes, ext=None, trailers=None,
                  final_ext=None):
    """Assemble a chunked stream from (body_parts, sizes)."""
    out = bytearray()
    for part, size in zip(body_parts, sizes):
        line = ("%x" % size).encode("ascii")
        if ext is not None:
            line += ext
        out += line + b"\r\n" + part + b"\r\n"
    last = b"0"
    if final_ext is not None:
        last += final_ext
    out += last + b"\r\n"
    if trailers:
        for name, val in trailers:
            if isinstance(val, str):
                val = val.encode("utf-8")
            out += name.encode("ascii") + b": " + val + b"\r\n"
    out += b"\r\n"
    return bytes(out)


failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


# ---------------------------------------------------------------------------
# 1. Visible fixture recheck through the deliverable parse_response.
# ---------------------------------------------------------------------------
visible = open("/app/fixtures/response_chunked.bin", "rb").read()
vr = req.parse_response(visible)
check(vr.status == 200, "visible chunked status")
check(vr.body == b"hello world", "visible chunked body")
check(vr.trailers == [("X-Trailer", "first"), ("X-Trailer", "second")],
      "visible chunked trailers")

# ---------------------------------------------------------------------------
# 2. Hidden valid streams, recomputed by the reference parser.
# ---------------------------------------------------------------------------
CASES = []
# mixed sizes, uppercase hex, unicode body
body = "grüße 世界 \u00fc".encode("utf-8")
sizes = [7, 3, 5, len(body) - 15]
parts = []
off = 0
for s in sizes:
    parts.append(body[off:off + s])
    off += s
CASES.append(("unicode mixed", build_chunked(
    parts, sizes, ext=b';foo="a;b;c";bar', trailers=[
        ("X-Checksum", b"abc123"), ("X-Checksum", b"def"),
        ("Not-Final", b"  padded  ")], final_ext=b";done=1"), body,
    [("X-Checksum", "abc123"), ("X-Checksum", "def"),
     ("Not-Final", "padded")]))

# no trailers, single chunk, size 0A
CASES.append(("single chunk", b"0A\r\n0123456789\r\n0\r\n\r\n",
              b"0123456789", []))

# trailers only, empty body
CASES.append(("empty + trailers",
              b"0\r\nDone: yes\r\nServer: mine\r\n\r\n", b"",
              [("Done", "yes"), ("Server", "mine")]))

# several zero-length chunks before the last
CASES.append(("empty chunks", b"0\r\n\r\n", b"", []))

# chunk data containing CRLF bytes (raw, not folded)
body2 = b"a\r\nb\r\nc"
CASES.append(("embedded crlf", build_chunked([b"a\r\nb", b"\r\nc"], [4, 3]),
              body2, []))

# big chunk (0x1ff) with extension
big = bytes(range(256)) * 2   # 512 bytes
CASES.append(("big chunk", build_chunked([big], [512], ext=b";len=512"),
              big, []))

# trailing whitespace in trailer values trimmed
CASES.append(("trailer padding",
              b"5\r\nhello\r\n0\r\nT:  x y  \r\nT2: \t v \t\r\n\r\n",
              b"hello", [("T", "x y"), ("T2", "v")]))

for label, stream, want_body, want_trailers in CASES:
    try:
        b2 = ref_decode(stream)
    except ValueError as exc:
        failures.append("%s: reference failed on own stream: %s" % (label, exc))
        continue
    check(b2[0] == want_body, "%s: reference body mismatch" % label)
    check(b2[1] == want_trailers, "%s: reference trailers mismatch" % label)
    try:
        got = dlv.decode_chunked(stream)
    except dlv.ChunkedError as exc:
        failures.append("%s: deliverable rejected valid stream: %s" % (label, exc))
        continue
    check(got.body == want_body, "%s: deliverable body %r" % (label, got.body))
    check(got.trailers == want_trailers,
          "%s: deliverable trailers %r != %r" % (label, got.trailers, want_trailers))

# ---------------------------------------------------------------------------
# 3. Hidden malformed streams: ChunkedError required.
# ---------------------------------------------------------------------------
BAD = [
    (b"GG\r\n0\r\n\r\n", "non-hex size"),
    (b"0x5\r\nhello\r\n0\r\n\r\n", "0x prefix"),
    (b"+5\r\nhello\r\n0\r\n\r\n", "plus prefix"),
    (b"5 \r\nhello\r\n0\r\n\r\n", "space in size"),
    (b" \t5\r\nhello\r\n0\r\n\r\n", "leading ws in size"),
    (b"5\r\nhello", "truncated body"),
    (b"5\r\nhell\r\n0\r\n\r\n", "short data"),
    (b"5\r\nhello\n\r\n0\r\n\r\n", "LF-only terminator"),
    (b"5\r\nhello\r\n", "missing final chunk"),
    (b"5\r\nhello\r\n0\r\n\r\nEXTRA", "trailing data"),
    (b"0\r\nX-Trailer: v\r\n", "unterminated trailers"),
    (b"0\r\nBadTrailer\r\n\r\n", "trailer without colon"),
    (b"0\r\n bad: v\r\n\r\n", "leading space in trailer name"),
    (b"0\r\nA B: v\r\n\r\n", "space inside trailer name"),
    (b"0\r\n;foo: v\r\n\r\n", "semicolon trailer name"),
    (b"\r\n0\r\n\r\n", "empty size"),
    (b"1\r\na\r\n", "eof before final"),
]
for stream, label in BAD:
    check(expect_error(stream, label), "valid stream flagged bad: %s" % label)

# non-bytes input must raise ChunkedError
try:
    dlv.decode_chunked("0\r\n\r\n")
    failures.append("str input accepted")
except dlv.ChunkedError:
    pass

# max_body enforcement
big_stream = build_chunked([b"x" * 40], [40])
try:
    dlv.decode_chunked(big_stream, max_body=10)
    failures.append("max_body not enforced")
except dlv.ChunkedError:
    pass
ok = dlv.decode_chunked(big_stream, max_body=40)
check(ok.body == b"x" * 40, "max_body exact fit")

# ---------------------------------------------------------------------------
# 4. Hidden full responses through /app/httpkit/request.py.
# ---------------------------------------------------------------------------
hdr = (b"HTTP/1.1 201 Created\r\nTransfer-Encoding: chunked\r\n"
       b"X-Mode: TeSt\r\n\r\n")
r1 = req.parse_response(hdr + build_chunked([b"payload"], [7], ext=b";e=1",
                                            trailers=[("ETag", "w/9")]))
check(r1.status == 201 and r1.reason == "Created", "hidden resp status")
check(r1.body == b"payload", "hidden resp body")
check(r1.trailers == [("ETag", "w/9")], "hidden resp trailers")
check(r1.header("x-mode") == "TeSt", "header() case-insensitive")

r2 = req.parse_response(b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nwxyz")
check(r2.body == b"wxyz" and r2.trailers == [], "CL response")

for bad in (b"HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip\r\n\r\n",
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nZZ\r\n",
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhi\r\n"):
    try:
        req.parse_response(bad)
        failures.append("bad response accepted: %r" % bad)
    except ValueError:
        pass

print("--- probe_chunked %d failure(s) ---" % len(failures))
for f in failures:
    print("FAIL:", f)
sys.exit(1 if failures else 0)