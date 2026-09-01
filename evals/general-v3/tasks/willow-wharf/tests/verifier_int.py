#!/usr/bin/env python3
"""willow-wharf integral verifier. Re-runs /app/integral.py on the hidden
integral specs in /tests/hidden/integral_cases.json and compares each printed
closed form to a freshly computed sympy reference. Also checks the visible
deliverable /app/integral.txt. Exits 0 on a full pass, nonzero otherwise."""
import subprocess
import sys

import sympy as sp

X = sp.Symbol("x")


def reference(expr_text):
    """Exact simplified closed form of int_0^1 <expr> dx (as a string)."""
    val = sp.integrate(sp.sympify(expr_text), (X, 0, 1))
    return str(sp.simplify(sp.expand(val)))


def run(expr_text):
    p = subprocess.run(
        ["python3", "/app/integral.py", expr_text],
        capture_output=True, text=True,
    )
    return p, p.stdout.strip(), p.stderr.strip()


fail = []
# -- fixed deliverable /app/integral.txt ------------------------------------
try:
    txt = open("/app/integral.txt", encoding="utf-8").read().strip()
except OSError:
    txt = ""
if txt != reference("4/(1+x**2)"):  # == "pi"
    fail.append("integral.txt != pi closed form")
else:
    print(f"  [ok] integral.txt == {txt!r}")

# -- hidden cases ------------------------------------------------------------
import json  # noqa: E402

spec = json.load(open("/tests/hidden/integral_cases.json", encoding="utf-8"))
for c in spec["cases"]:
    e = c["expr"]
    if c.get("kind") == "error":
        p, out, err = run(e)
        ok = p.returncode == 2 and len(out) == 0 and len(err) > 0
        if ok:
            print(f"  [ok] malformed {e!r} rejected (exit 2)")
        else:
            fail.append(f"malformed {e!r}: rc={p.returncode} out={out!r} err={err!r}")
        continue
    want = c.get("expect") or reference(e)
    p, out, err = run(e)
    if p.returncode != 0:
        fail.append(f"{e!r}: exit {p.returncode} stderr={err!r}")
    elif out != want:
        fail.append(f"{e!r}: got {out!r} want {want!r}")
    else:
        print(f"  [ok] {e!r} == {want!r}")

rc = 1 if fail else 0
sys.exit(rc)