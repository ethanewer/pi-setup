#!/bin/bash
set -euo pipefail

cat > /app/sanitize.py <<'PYEOF'
"""Robust whitelist-based HTML sanitizer (contract implementation)."""
import html
from html.parser import HTMLParser

ALLOWED = {"b", "i", "strong", "em", "p", "br", "code", "pre", "span",
           "ul", "ol", "li", "blockquote", "a", "h1", "h2", "h3"}
DANGEROUS = {"script", "iframe", "style", "svg", "math", "object", "embed",
             "applet", "video", "audio", "form", "base", "meta", "link",
             "noscript", "template"}


def _safe_href(href):
    if href is None:
        return False
    h = href.strip()
    if not h:
        return False
    if h.startswith("#") or h.startswith("/"):
        return True
    low = h.lower()
    return low.startswith(("http://", "https://", "mailto:"))


def sanitize_html(user_input):
    class P(HTMLParser):
        def __init__(self):
            super().__init__(convert_charrefs=True)
            self.parts = []
            self.drop = 0

        def handle_starttag(self, tag, attrs):
            t = tag.lower()
            if t in DANGEROUS:
                self.drop += 1
            elif self.drop == 0:
                if t == "br" and t in ALLOWED:
                    self.parts.append("<br>")
                elif t in ALLOWED:
                    if t == "a":
                        href = None
                        for k, v in attrs:
                            if k.lower() == "href":
                                href = v
                                break
                        if _safe_href(href):
                            self.parts.append('<a href="%s">' % html.escape(href, quote=True))
                        else:
                            self.parts.append("<a>")
                    else:
                        self.parts.append("<%s>" % t)

        def handle_startendtag(self, tag, attrs):
            t = tag.lower()
            if self.drop == 0 and t in ALLOWED and t == "br":
                self.parts.append("<br>")
            elif self.drop == 0 and t in ALLOWED:
                if t == "a":
                    self.handle_starttag(tag, attrs)
                else:
                    self.parts.append("<%s></%s>" % (t, t))

        def handle_endtag(self, tag):
            t = tag.lower()
            if t in DANGEROUS:
                if self.drop > 0:
                    self.drop -= 1
            elif self.drop == 0 and t in ALLOWED and t != "br":
                self.parts.append("</%s>" % t)

        def handle_data(self, data):
            if self.drop == 0:
                self.parts.append(html.escape(data, quote=True))

        def handle_comment(self, data):
            pass

        def handle_decl(self, decl):
            pass

    p = P()
    p.feed(user_input)
    return "".join(p.parts)
PYEOF

python3 /app/check_sanitize.py

mkdir -p /app/tests
cat > /app/tests/test_sanitizer.py <<'PYEOF'
import sys

import pytest

sys.path.insert(0, "/app")
from sanitize import sanitize_html

SAFE_CASES = [
    ("<p>Hello <b>world</b> 123</p>", ["Hello", "world", "<p>", "<b>"]),
    ("<i>it</i> &amp; text", ["<i>it</i>", "&amp;"]),
    ("<em>E1</em><strong>S</strong>", ["<em>E1</em>", "<strong>S</strong>"]),
    ("<ul><li>x</li><li>y</li></ul>", ["<ul>", "<li>x</li>", "<li>y</li>"]),
    ('<a href="https://example.com/p">link</a>', ['<a href="https://example.com/p">', "link"]),
]

DANGEROUS_CASES = [
    ("<script>alert(1)</script>", ["<script"]),
    ("<SCRIPT src=http://evil/x.js></SCRIPT>", ["<script", "src="]),
    ("<img src=x onerror=alert(1)>", ["onerror="]),
    ('<a href="javascript:alert(1)">x</a>', ["javascript:"]),
    ('<iframe srcdoc="<script>alert(1)</script>"></iframe>', ["iframe"]),
    ("<svg onload=alert(1)></svg>", ["svg"]),
    ("<BODY onload=alert(1)>t</BODY>", ["onload="]),
    ('<a href="jav&#x61;script:alert(1)">z</a>', ["javascript:"]),
]


@pytest.mark.parametrize("inp,expected", SAFE_CASES)
def test_safe_preserved(inp, expected):
    out = sanitize_html(inp)
    for tok in expected:
        assert tok in out, (inp, tok, out)


@pytest.mark.parametrize("inp,banned", DANGEROUS_CASES)
def test_dangerous_stripped(inp, banned):
    out = sanitize_html(inp).lower()
    for tok in banned:
        assert tok.lower() not in out, (inp, tok, out)


def test_text_escaped():
    assert sanitize_html("a < b & c") == "a &lt; b &amp; c"
PYEOF

cd /app && python3 -m pytest tests -q