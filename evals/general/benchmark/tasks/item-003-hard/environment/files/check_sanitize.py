#!/usr/bin/env python3
"""Supplied evaluator for item-003 (hard).

Imports /app/sanitize.sanitize_html and checks:

  1. SAFE inputs keep their allowed markup/text (presence checks);
  2. well-formed safe inputs must round-trip to the *identical* string under
     the canonical serialization rules of the contract;
  3. DANGEROUS inputs must not let any forbidden token survive (including
     entity-encoded schemes, nested dangerous elements, self-closing
     variants, attribute-less event handlers).

Prints PASS/FAIL per case and writes the verdict to /app/status.txt.
"""

import sys

import sanitize

# (input, [must-be-present])
SAFE = [
    ("<p>Hello <b>world</b> 123</p>", ["Hello", "world", "<p>", "<b>"]),
    ("<i>it</i> &amp; text", ["<i>it</i>", "&amp;"]),
    ("<em>E1</em><strong>S</strong>", ["<em>E1</em>", "<strong>S</strong>"]),
    ("<ul> <li>x</li> <li>y</li> </ul>", ["<ul>", "<li>x</li>", "<li>y</li>", "</ul>"]),
    ('<a href="https://example.com/p">link</a>', ['<a href="https://example.com/p">', "link</a>"]),
    ("<h1>Head</h1> tail", ["<h1>", "tail"]),
]

# canonical, well-formed safe inputs that must round-trip EXACTLY:
FORMAT_EXACT = [
    "<p>Hello <b>world</b></p>",
    "<em>E1</em><strong>S</strong>",
    '<a href="https://example.com/p">link</a>',
    "<ul><li>x</li></ul>",
]

# (input, [forbidden], [required-preserved])
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


def main():
    ok = True

    def report(name, cond):
        nonlocal ok
        print((name + " PASS") if cond else (name + " FAIL"))
        if not cond:
            ok = False

    for idx, (inp, want) in enumerate(SAFE):
        out = sanitize.sanitize_html(inp)
        report("safe[%d]" % idx, all(tok in out for tok in want))

    for idx, inp in enumerate(FORMAT_EXACT):
        out = sanitize.sanitize_html(inp)
        report("format[%d]" % idx, out == inp)

    for idx, (inp, banned, req) in enumerate(DANGEROUS):
        out = sanitize.sanitize_html(inp)
        low = out.lower()
        cond = all(tok.lower() not in low for tok in banned)
        if cond and req:
            cond = all(tok in out for tok in req)
        report("danger[%d]" % idx, cond)

    with open("/app/status.txt", "w") as f:
        f.write("PASS\n" if ok else "FAIL\n")
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())