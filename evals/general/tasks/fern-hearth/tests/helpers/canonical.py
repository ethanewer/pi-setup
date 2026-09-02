"""Canonical repository-URL normalizer used by the verifier helpers.

Independent implementation of the canonical form the task's /app/normalize_url.py
must reproduce. Rules (see task instruction.md):
  * leading/trailing ASCII whitespace is stripped;
  * a line without an explicit "://" scheme is malformed and passed through
    unchanged (strip whitespace only);
  * scheme is lower-cased; netloc host is lower-cased;
  * a default port for the scheme (http:80, https:443, ftp:21) is dropped;
  * all trailing '/' are stripped from the path ('/' -> '');
  * query parameters are sorted by key (stable), empty query dropped;
  * any fragment is dropped;
  * blank lines map to blank lines.
"""
from urllib.parse import urlsplit

DEFAULT_PORTS = {"http": 80, "https": 443, "ftp": 21}


def canonicalize(s):
    if "\n" in s:
        s = s.rstrip("\n")
    if s.strip() == "":
        return ""
    raw = s
    u = s.strip()
    if "://" not in u:
        return u  # malformed/non-absolute: pass-through (whitespace stripped)
    p = urlsplit(u)
    scheme = p.scheme.lower()
    if not scheme:
        return u

    host = (p.hostname or "").lower()
    port = p.port
    if port is not None and port == DEFAULT_PORTS.get(scheme):
        port = None

    userinfo = ""
    if p.username is not None:
        userinfo = p.username
        if p.password is not None:
            userinfo += ":" + p.password
        userinfo += "@"

    netloc = userinfo + host
    if port is not None:
        netloc += ":" + str(port)

    path = p.path or ""
    if path:
        path = path.rstrip("/")

    params = [x for x in p.query.split("&") if x]
    params.sort(key=lambda x: x.split("=", 1)[0])
    q = "&".join(params)

    out = scheme + "://" + netloc + path
    if q:
        out += "?" + q
    return out


def normalize_lines(text):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return [canonicalize(l) for l in lines]