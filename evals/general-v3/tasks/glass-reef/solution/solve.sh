#!/bin/bash
# Oracle for tasks/glass-reef.
# Writes the deliverable /app/clean.py (a real sanitizer), makes it executable,
# then smoke-tests it against locally generated benign and adversarial inputs.
set -euo pipefail

mkdir -p /app

cat > /app/clean.py <<'PYEOF'
#!/usr/bin/env python3
"""Sanitize an HTML fragment while preserving benign structure.

Usage: python3 clean.py INPUT OUTPUT
Reads a UTF-8 HTML fragment from INPUT and writes a sanitized fragment to
OUTPUT. Never modifies INPUT. Exits 0 on success, non-zero on error.
"""
import sys
import re
from html.parser import HTMLParser

VOID = {'area','base','br','col','embed','hr','img','input','link','meta',
        'param','source','track','wbr'}
BLOCKALL = {'script','style','template','iframe','object','embed','svg',
            'math','link','meta','base','title','frame','frameset','noscript'}
ALLOWED = {
    'p','div','span','b','strong','i','em','u','s','sub','sup','mark','small',
    'h1','h2','h3','h4','h5','h6',
    'ul','ol','li','dl','dt','dd','blockquote','pre','code','abbr','cite',
    'a','img','br','hr',
    'table','caption','thead','tbody','tfoot','tr','td','th'}
SAFE_ATTR = {'href','src','alt','title','rel','target','id','class',
             'colspan','rowspan','name','value'}
URL_ATTRS = {'href','src','action','formaction','poster','cite'}
GOOD_SCHEMES = {'http','https','mailto','ftp','tel','sms','irc','urn',
                'xmpp','news','nntp'}


def _url_ok(value):
    v = (value or '').strip()
    v = re.sub(r'^[\s\u0000-\u0008\u000b-\u001f\u00ad\u200b\u200c\u200d]+',
               '', v)
    m = re.match(r'^([a-zA-Z][a-zA-Z0-9+.\-]*)\s*:', v)
    if not m:
        return True  # relative, protocol-relative (//), fragment-only
    scheme = m.group(1).lower()
    return scheme in GOOD_SCHEMES


def _esc(v, attr=False):
    v = v.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    if attr:
        v = v.replace('"', '&quot;')
    return v


class Curator(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self._out = []
        self._blocked = 0

    def _emit(self, s):
        if self._blocked == 0:
            self._out.append(s)

    def _open(self, tag, attrs, void):
        self._emit('<')
        self._emit(tag)
        seen = set()
        for (n, v) in attrs:
            n = (n or '').strip().lower()
            if not n or n in seen:
                continue
            seen.add(n)
            if n.startswith('on'):
                continue
            if n not in SAFE_ATTR:
                continue
            if n in URL_ATTRS and not _url_ok(v):
                continue
            self._emit(' ' + n + '="' + _esc(v if v is not None else '',
                                             True) + '"')
        self._emit('/>') if void else self._emit('>')

    def handle_starttag(self, tag, attrs):
        tag = tag.strip().lower()
        if tag in BLOCKALL:
            self._blocked += 1
            return
        if tag in ALLOWED:
            self._open(tag, attrs, tag in VOID)

    def handle_startendtag(self, tag, attrs):
        tag = tag.strip().lower()
        if tag in BLOCKALL:
            return
        if tag in ALLOWED:
            self._open(tag, attrs, True)

    def handle_endtag(self, tag):
        tag = tag.strip().lower()
        if tag in BLOCKALL:
            if self._blocked > 0:
                self._blocked -= 1
            return
        if tag in ALLOWED and tag not in VOID:
            self._emit('</' + tag + '>')

    def handle_data(self, data):
        if data:
            self._emit(_esc(data))

    def handle_comment(self, data):
        pass

    def handle_decl(self, decl):
        pass

    def handle_pi(self, data):
        pass


def sanitize(text):
    cur = Curator()
    try:
        cur.feed(text)
        cur.close()
    except Exception:
        return ''
    return ''.join(cur._out)


def main(argv):
    if len(argv) != 2:
        sys.stderr.write('usage: clean.py INPUT OUTPUT\n')
        return 2
    src, dst = argv
    with open(src, 'r', encoding='utf-8') as f:
        text = f.read()
    result = sanitize(text)
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(result)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
PYEOF

chmod +x /app/clean.py

# ---- smoke-test the installed program on our own locally generated inputs ----
# (predicted safe outputs are asserted inline; no /tests is read)
T=$(mktemp -d)

# benign fragment: expected safe content
cat > "$T/benign.html" <<'HT'
<p>Hi, <a href="https://docs.example.com/guide">read this</a>.</p>
HT
python3 /app/clean.py "$T/benign.html" "$T/benign.out"
grep -q '<p>Hi' "$T/benign.out"
grep -q 'href="https://docs.example.com/guide"' "$T/benign.out"

# adversarial fragment: script, comment, event attribute, javascript/data URLs
cat > "$T/bad.html" <<'HT'
<!-- leak --><script>alert(1)</script>
<p onclick="steal()">ok</p>
<a href="javascript:alert(1)">bad</a>
<a href="data:text/html,x">d</a>
<a href="https://safe.example/">fine</a>
HT
python3 /app/clean.py "$T/bad.html" "$T/bad.out"
# dangerous constructs must be gone
! grep -q 'script' "$T/bad.out"
! grep -q 'onclick' "$T/bad.out"
! grep -q 'javascript:' "$T/bad.out"
! grep -q 'data:' "$T/bad.out"
! grep -q '<!--' "$T/bad.out"
# safe link kept
grep -q 'href="https://safe.example/"' "$T/bad.out"
grep -q '>ok<' "$T/bad.out"
grep -q '>bad<' "$T/bad.out"

# plain text + empty input
printf '' > "$T/empty.html"
python3 /app/clean.py "$T/empty.html" "$T/empty.out"
[ ! -s "$T/empty.out" ]

rm -rf "$T"
echo "oracle: clean.py installed and smoke-tested"