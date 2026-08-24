"""Cookie header construction. The HTTP response-header security boundary lives
here: `build` returns the value written into the `Set-Cookie` response header.

SSRF/CWE-93 relevance: the `payload` string is attacker-influenced and is
currently placed into the header verbatim. Any CR/LF bytes in it will split the
HTTP response line and inject an arbitrary extra header.
"""
import re

_CRLF = re.compile(r'[\r\n]+')


def build(payload, flag):
    """Return a single-line Set-Cookie header value.

    `payload` originates from external input; it must never be allowed to
    terminate the header line.
    """
    return "%s; HttpOnly; %s" % (payload, flag)