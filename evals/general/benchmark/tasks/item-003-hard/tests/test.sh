#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/sanitize.py ]; then
  if python3 - <<'PYEOF'
import sys
sys.path.insert(0, "/app")
import sanitize

SAFE = [
    ("<p>Hello <b>world</b> 123</p>", ["Hello", "world", "<p>", "<b>"]),
    ("<i>it</i> &amp; text", ["<i>it</i>", "&amp;"]),
    ("<em>E1</em><strong>S</strong>", ["<em>E1</em>", "<strong>S</strong>"]),
    ("<ul> <li>x</li> <li>y</li> </ul>", ["<ul>", "<li>x</li>", "<li>y</li>", "</ul>"]),
    ('<a href="https://example.com/p">link</a>', ['<a href="https://example.com/p">', "link</a>"]),
    ("<h1>Head</h1> tail", ["<h1>", "tail"]),
]

FORMAT_EXACT = [
    "<p>Hello <b>world</b></p>",
    "<em>E1</em><strong>S</strong>",
    '<a href="https://example.com/p">link</a>',
    "<ul><li>x</li></ul>",
]

DANGEROUS = [
    ("<script>alert(1)</script>", ["<script"], []),
    ("<SCRIPT src=http://evil/x.js></SCRIPT>", ["<script", "src="], []),
    ("<img src=x onerror=alert(1)>", ["onerror="], []),
    ('<img src="javascript:alert(1)">', ["javascript:"], []),
    ('<iframe srcdoc="<script>alert(1)</script>"></iframe>', ["iframe", "srcdoc"], []),
    ('<a href="javascript:alert(1)">click</a>', ["javascript:"], ["click"]),
    ("<BODY onload=alert(1)>t</BODY>", ["onload="], ["t"]),
    ("<style>body{color:red}</style>", ["style"], []),
    ('<a href="jav&#x61;script:alert(1)">x</a>', ["javascript:"], ["x"]),
    ("<svg onload=alert(1)></svg>", ["svg", "onload="], []),
    ("<svg><script>alert(1)</script></svg>", ["svg", "<script"], []),
    ("<img/src=x onerror=alert(1)>", ["onerror="], []),
    ('<a onmouseover="alert(1)" href="/rel">ok</a>', ["onmouseover=", "alert"], ['href="/rel"', "ok"]),
    ("<a href=jav&#x0a;ascript:alert(1)>e</a>", ["javascript:"], ["e"]),
    ('<iframe src="data:text/html;base64,PHNjcmlwdA=="></iframe>', ["iframe", "data:"], []),
    ("<details open ontoggle=alert(1)>d</details>", ["ontoggle="], ["d"]),
]

for inp, want in SAFE:
    out = sanitize.sanitize_html(inp)
    if not all(tok in out for tok in want):
        print("safe fail %r -> %r" % (inp, out)); sys.exit(1)

for inp in FORMAT_EXACT:
    out = sanitize.sanitize_html(inp)
    if out != inp:
        print("format fail %r -> %r" % (inp, out)); sys.exit(1)

for inp, banned, req in DANGEROUS:
    out = sanitize.sanitize_html(inp)
    low = out.lower()
    if any(tok.lower() in low for tok in banned):
        print("danger fail %r -> %r" % (inp, out)); sys.exit(1)
    if req and not all(tok in out for tok in req):
        print("required-text fail %r -> %r" % (inp, out)); sys.exit(1)
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt