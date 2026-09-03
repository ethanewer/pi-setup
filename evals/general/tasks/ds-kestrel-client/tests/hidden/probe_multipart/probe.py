#!/usr/bin/env python3
"""ds-kestrel-client hidden probe: multipart/form-data body building.

Holds hidden part lists (generated here, never seen by the agent) and
re-derives the expected request/body bytes with an independent reference
encoder; compares byte-for-byte against /app/httpkit/multipart.py and the
full build_request flow in /app/httpkit/request.py.  Also checks
make_boundary/content_type determinism and ValueError validation, and
re-runs the visible /app/fixtures multipart request through the
deliverables.

Exit code 0 = pass, 1 = fail.
"""
import base64
import sys

sys.path.insert(0, "/app")
import httpkit.multipart as dlv
import httpkit.request as req

# ---------------------------------------------------------------------------
# Independent reference encoder (derived from the documented contract;
# deliberately a different structure than the library implementation).
# ---------------------------------------------------------------------------


def ref_escape(text):
    out = []
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        else:
            out.append(ch)
    return "".join(out)


def ref_encode(parts, boundary):
    """Byte-level re-encoding straight from the documented emission rules."""
    out = bytearray()
    for part in parts:
        if part[0] == "field":
            _, name, value = part
            out += ("--%s\r\n" % boundary).encode("ascii")
            out += ('Content-Disposition: form-data; name="%s"\r\n'
                    % ref_escape(name)).encode("utf-8")
            out += b"\r\n"
            out += value.encode("utf-8") if isinstance(value, str) else value
            out += b"\r\n"
        elif part[0] == "file":
            _, name, filename, ctype, content = part
            out += ("--%s\r\n" % boundary).encode("ascii")
            out += ('Content-Disposition: form-data; name="%s"; '
                    'filename="%s"\r\n'
                    % (ref_escape(name), ref_escape(filename))).encode("utf-8")
            if ctype:
                out += ("Content-Type: %s\r\n" % ctype).encode("utf-8")
            out += b"\r\n"
            out += content.encode("utf-8") if isinstance(content, str) \
                else content
            out += b"\r\n"
        else:
            raise ValueError("bad shape")
    out += ("--%s--\r\n" % boundary).encode("ascii")
    return bytes(out)


failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


# ---------------------------------------------------------------------------
# 1. Visible multipart request recheck through the deliverables.
# ---------------------------------------------------------------------------
with open("/app/fixtures/request_multipart.bin", "rb") as fh:
    visible_blob = fh.read()
bvis = dlv.make_boundary(1)
parts_vis = [("field", "username", "kestrel_fan"),
             ("field", "comment", "hello \u00fcn\u00efcode \u2603"),
             ("file", "avatar", "head shot.png", "image/png",
              b"\x89PNG\r\n\x1a\n"),
             ("field", "empty", ""),
             ("file", "manifest", "m.txt", "", "hello manifest")]
check(ref_encode(parts_vis, bvis) == dlv.multipart_encode(parts_vis, bvis),
      "visible multipart body vs reference")
got = req.build_request("POST", "/upload",
                        [("Host", "fixture.test"),
                         ("Content-Type", dlv.content_type(bvis))],
                        body=dlv.multipart_encode(parts_vis, bvis))
check(got == visible_blob, "visible multipart request bytes")

# ---------------------------------------------------------------------------
# 2. Hidden part lists, bytes recomputed by the reference encoder.
# ---------------------------------------------------------------------------
CASES = [
    # (label, boundary, parts)
    ("escaping", "----hkit0a11bb22cc33dd44", [
        ("field", 'who"\\"', "v1"),
        ("field", "tab name", "v2"),
        ("file", "quote\"file", 'na"me\\x.png', "application/octet-stream",
         b"\x00\x01\x02"),
    ]),
    ("unicode everywhere", "bnd4ta", [
        ("field", "ünï", "значение ✓"),
        ("file", "имя", "файл.txt", "text/plain; charset=utf-8",
         "snowman ☃ \u2603"),
        ("field", "empty", ""),
    ]),
    ("special boundary chars", "a+b/c:d'e(f)g", [
        ("field", "k1", "value with boundary a+b/c:d'e(f)g inside"),
        ("file", "k2", "x", "", "no content type"),
    ]),
    ("binary file content", "0123456789abcdef", [
        ("file", "bin", "img.bin", "image/png",
         bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        ("file", "txt", "note.txt", "text/plain", "hi\r\nplain"),
    ]),
    ("many ordered parts", "bb", [
        ("field", "f%02d" % i, "value-%02d" % i)
        if i % 3 else ("file", "f%02d" % i, "file-%02d.bin" % i,
                       "application/x" if i % 2 else "",
                       b"content-%02d" % i)
        for i in range(18)
    ]),
    ("bare crlf values", "zz", [
        ("field", "a", "line1\r\nline2"),
        ("field", "b", "endswithcrlf\r\n"),
    ]),
]
for label, boundary, parts in CASES:
    want = ref_encode(parts, boundary)
    got = dlv.multipart_encode(parts, boundary)
    check(got == want, "%s: multipart_encode bytes mismatch\n  got= %r\n  want=%r"
          % (label, got, want))

# ---------------------------------------------------------------------------
# 3. make_boundary / content_type determinism.
# ---------------------------------------------------------------------------
for seed in (0, 1, 0xDEADBEEF, 2 ** 64 - 1, 12345678901234567890123):
    want = "----hkit%016x" % (seed & 0xFFFFFFFFFFFFFFFF)
    check(dlv.make_boundary(seed) == want, "make_boundary(%r)" % seed)
check(dlv.content_type("b1") == "multipart/form-data; boundary=b1",
      "content_type")

# ---------------------------------------------------------------------------
# 4. ValueError validation.
# ---------------------------------------------------------------------------
def raises(fn, label):
    try:
        fn()
    except ValueError:
        return
    failures.append("no ValueError: %s" % label)


raises(lambda: dlv.multipart_encode([("field", "", "v")], "b"),
       "empty name")
raises(lambda: dlv.multipart_encode([("field", "a\nb", "v")], "b"),
       "control char in name")
raises(lambda: dlv.multipart_encode([("file", "a", "x\x7fy", "t", b"")], "b"),
       "DEL in filename")
raises(lambda: dlv.multipart_encode([("field", "a", 5)], "b"),
       "non str/bytes value")
raises(lambda: dlv.multipart_encode([("wut", "a", "b", "c")], "b"),
       "unknown shape (4 tuple)")
raises(lambda: dlv.multipart_encode([("field", "a", "v")], "b\r\n"),
       "boundary with CRLF")
raises(lambda: dlv.multipart_encode([("field", "a", "v", 1)], "b"),
       "bad field arity")

# ---------------------------------------------------------------------------
# 5. Hidden full requests through build_request.
# ---------------------------------------------------------------------------
hidden_parts = [("field", "token", "9a8b7c"),
                ("file", "report", "r1.txt", "text/plain",
                 "alpha: 1\r\nbeta: 2"),
                ("field", "empty", "")]
boundary = "----hkit0000ffff0000ffff"
hbody = ref_encode(hidden_parts, boundary)
hreq = req.build_request(
    "POST", "/ingest",
    [("Host", "hidden.test"),
     ("Content-Type", "multipart/form-data; boundary=" + boundary)],
    body=dlv.multipart_encode(hidden_parts, boundary))
want_head = ("POST /ingest HTTP/1.1\r\n"
             "Host: hidden.test\r\n"
             "Content-Type: multipart/form-data; boundary=" + boundary +
             "\r\nContent-Length: %d\r\n\r\n" % len(hbody)).encode("ascii")
check(hreq == want_head + hbody, "hidden build_request bytes")
# content-length must be auto-appended and exact
check(hreq.count(b"Content-Length:") == 1, "exactly one Content-Length")

hreq2 = req.build_request(
    "POST", "/any",
    [("X-A", "1"), ("content-length", str(len(hbody))),
     ("X-B", "2")],
    body=dlv.multipart_encode(hidden_parts, boundary))
check(hreq2.startswith(b"POST /any HTTP/1.1\r\nX-A: 1\r\n"
                       b"content-length: %d\r\nX-B: 2\r\n\r\n" % len(hbody)),
      "existing CL kept in place")
try:
    req.build_request("POST", "/x", [("Content-Length", "1")],
                      body=b"long")
    failures.append("CL mismatch not rejected")
except ValueError:
    pass

print("--- probe_multipart %d failure(s) ---" % len(failures))
for f in failures:
    print("FAIL:", f)
sys.exit(1 if failures else 0)