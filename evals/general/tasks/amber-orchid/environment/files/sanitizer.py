"""sanitizer.py -- shared HTML filter for the Merkstock comment view.

This is a SHARED, PROVIDED module (you must not modify it). The verifier uses
the same copy from /app. It removes:
  * <script>...</script> elements,
  * event-handler attributes that immediately follow whitespace,
  * javascript: URLs,
  * a fixed blacklist of element tag names.
"""
import re

_BLACKED_TAGS = {
    "script", "img", "iframe", "object", "embed", "video", "audio",
    "form", "input", "button", "textarea", "select", "style", "link",
    "meta", "base",
}

_ON_PAT = re.compile(r"\s+on[a-zA-Z][a-zA-Z0-9_\-]*\s*=")
_JS_URL = re.compile(r"((?:href|src)\s*=\s*)(['\"]?)javascript:\s*", re.I)
_TAG = re.compile(r"<([a-zA-Z][a-zA-Z0-9-]*)")


def _fix_tag(m):
    tag = m.group(1).lower()
    return m.group(0) if tag not in _BLACKED_TAGS else "&lt;" + tag


def sanitize(html):
    """Return `html` with the blacklisted constructs neutralized."""
    if not isinstance(html, str):
        return ""
    out = html
    out = out.replace("<script", "&lt;script").replace("</script", "&lt;/script")
    out = _JS_URL.sub("", out)
    out = _TAG.sub(_fix_tag, out)
    out = _ON_PAT.sub(" ", out)
    return out