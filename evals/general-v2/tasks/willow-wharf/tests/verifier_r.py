#!/usr/bin/env python3
"""willow-wharf R verifier. Loads /app/sampler.R, checks the two required
entry-point names appear verbatim, evaluates willow_sample on the hidden
sampler specs in /tests/hidden/sampler_cases.json, re-runs willow_selftest()
(exit 0 + PASS), and checks the shipped /app/selftest.log. Exits 0 on pass."""
import json
import os
import re
import subprocess
import sys

fail = []

SRC = "/app/sampler.R"


def R(script):
    return subprocess.run(
        ["Rscript", "-e", script], capture_output=True, text=True,
    )


# -- required entry-point names ----------------------------------------------
if not os.path.exists(SRC):
    print("  [FAIL] /app/sampler.R missing")
    sys.exit(1)
src = open(SRC, encoding="utf-8").read()
for name in ("willow_sample", "willow_selftest"):
    if re.search(r"^" + name + r"\s*<-", src, re.M):
        print(f"  [ok] entry point {name}")
    else:
        fail.append(f"required entry point {name} not found verbatim")

# -- shipped selftest.log ----------------------------------------------------
if os.path.exists("/app/selftest.log"):
    if "PASS" in open("/app/selftest.log", encoding="utf-8").read():
        print("  [ok] selftest.log contains PASS")
    else:
        fail.append("selftest.log does not contain PASS")
else:
    fail.append("selftest.log missing")

# -- hidden sampler cases ----------------------------------------------------
spec = json.load(open("/tests/hidden/sampler_cases.json", encoding="utf-8"))
for c in spec["cases"]:
    n, a = c["n"], c["a"]
    edge = c.get("edge", False)
    p = R(f'source("/app/sampler.R"); v <- willow_sample({n},{a}); cat(v)')
    if p.returncode != 0:
        fail.append(f"willow_sample({n},{a}) errored: {p.stderr.strip()!r}")
        continue
    try:
        got = float(p.stdout.strip())
    except ValueError:
        fail.append(f"willow_sample({n},{a}) non-numeric {p.stdout!r}")
        continue
    if edge:
        if not (got == got and got not in (float("inf"), float("-inf"))):
            fail.append(f"edge n={n}: got {got} not finite")
        else:
            print(f"  [ok] edge n={n} finite")
        continue
    want = 1.0 / (a + 1.0)
    tol = c.get("tol", 0.05)
    if abs(got - want) <= tol:
        print(f"  [ok] n={n} a={a} got={got:.4f} near {want:.4f}")
    else:
        fail.append(f"n={n} a={a} got={got!r} vs ~{want!r} (tol {tol})")

# -- independent self-test re-run --------------------------------------------
p = R('source("/app/sampler.R"); willow_selftest()')
if p.returncode == 0 and "PASS" in p.stdout:
    print("  [ok] willow_selftest re-run exits 0 with PASS")
else:
    fail.append(f"willow_selftest re-run rc={p.returncode} out={p.stdout.strip()!r}")

sys.exit(1 if fail else 0)