#!/usr/bin/env python3
"""Supplied evaluator for item-003.

Imports /app/sanitize.sanitize_html and runs it against a corpus of safe and
dangerous inputs, checking the exact contract properties described in the
instructions. Prints one PASS/FAIL line per input and writes the overall
verdict to /app/status.txt.

Safety contract (per instruction):
  SAFE inputs: text content and allowed formatting must survive.
  DANGEROUS inputs: no executable markup may survive.
"""

import sys

import sanitize

# (input, [must-be-present substrings])
SAFE = [
    ("<p>Hello <b>world</b> 123</p>", ["Hello", "world", "<p>", "<b>"]),
    ("<i>it</i> &amp; text", ["<i>it</i>", "&amp;"]),
    ("<em>E1</em><strong>S</strong>", ["<em>E1</em>", "<strong>S</strong>"]),
    ("<ul> <li>x</li> <li>y</li> </ul>", ["<ul>", "<li>x</li>", "<li>y</li>", "</ul>"]),
    ('<a href="https://example.com/p">link</a>', ['<a href="https://example.com/p">', "link</a>"]),
    ("<h1>Head</h1> tail", ["<h1>Head</h1>", "tail"]),
]

# (input, [forbidden substrings, case-insensitive, after html.unescape])
DANGEROUS = [
    ("<script>alert(1)</script>", ["<script"]),
    ("<SCRIPT src=http://evil/x.js></SCRIPT>", ["<script", "src="]),
    ("<img src=x onerror=alert(1)>", ["onerror="]),
    ('<img src="javascript:alert(1)">', ["javascript:"]),
    ('<iframe srcdoc="<script>alert(1)</script>"></iframe>', ["iframe", "srcdoc"]),
    ('<a href="javascript:alert(1)">click</a>', ["javascript:"]),
    ("<BODY onload=alert(1)>t</BODY>", ["onload="]),
    ("<style>body{color:red}</style>", ["style"]),
    ('<a href="jav&#x61;script:alert(1)">x</a>', ["javascript:"]),
    ("<svg onload=alert(1)></svg>", ["svg", "onload="]),
]


def main():
    fails = 0
    ok = True

    def report(name, cond):
        nonlocal ok, fails
        print((name + " PASS") if cond else (name + " FAIL"))
        if not cond:
            ok = False
            fails += 1

    for idx, (inp, want) in enumerate(SAFE):
        out = sanitize.sanitize_html(inp)
        cond = all(tok in out for tok in want)
        report("safe[%d]" % idx, cond)

    for idx, (inp, banned) in enumerate(DANGEROUS):
        out = sanitize.sanitize_html(inp)
        low = out.lower()
        cond = all(tok.lower() not in low for tok in banned)
        report("danger[%d]" % idx, cond)

    with open("/app/status.txt", "w") as f:
        f.write("PASS\n" if ok else "FAIL\n")
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())