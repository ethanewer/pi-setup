"""httpkit.request - request building and response parsing (base edition).

The current edition only supports simple requests (no request body) and
Content-Length-framed responses.  The task extends this module per the
documented contract: ``build_request`` gains a ``body`` parameter, and
``parse_response`` gains chunked transfer-encoding decoding (surfacing
trailers) through the new ``httpkit.chunked`` module.  Everything here is
pure bytes in / bytes out; no network I/O happens anywhere in the library.
"""

import re

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
        """Value of the first header whose name matches case-insensitively,
        or None."""
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


def build_request(method, path, headers=None):
    """Build one HTTP/1.1 request as bytes (base edition: no body support).

    ``method`` must be one or more ASCII letters; ``path`` must be a
    non-empty string starting with '/' that contains no CR or LF.  ``headers``
    is an ordered sequence of (name, value) pairs (or a dict, using its
    insertion order); they are written verbatim in that order.  The request
    always ends with CRLF CRLF.

    The extended edition documented in the task brief adds a ``body``
    parameter and automatic Content-Length handling.
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

    lines = ["%s %s HTTP/1.1" % (method, path)]
    for name, value in header_items:
        _check_header_line(name, value)
        lines.append("%s: %s" % (name, value))
    return ("\r\n".join(lines) + "\r\n\r\n").encode("ascii")


def parse_response(data):
    """Parse a full HTTP response (status line, headers, body) from bytes.

    Base edition: only Content-Length framing is supported; a chunked
    Transfer-Encoding raises ValueError until ``httpkit.chunked`` is wired
    in.  Raises ValueError on malformed status lines, headers, or framing.
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

    low = {n.lower(): v for n, v in headers}
    te = low.get("transfer-encoding")
    if te is not None:
        if "chunked" not in te.lower():
            raise ValueError("unsupported transfer-encoding")
        raise ValueError("chunked responses are not supported yet")
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