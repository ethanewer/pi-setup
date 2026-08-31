#!/bin/bash
# Verifier for dusk-anvil: re-builds and re-installs the package from the
# agent's repaired /app/hexcore tree, enforces the no-tamper rule on the
# bundled test suite, runs the visible pytest suite, and executes the
# installed extension against hidden probe cases. Writes REWARD to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# ---- deliverables present + no removed numpy C API flag anywhere in tree
pre_ok=1
for f in /app/hexcore/setup.py /app/hexcore/hexcore/_engine.pyx /app/hexcore/hexcore/_arrays.c; do
    if [ ! -f "$f" ]; then
        echo "missing deliverable $f" >&2
        pre_ok=0
    fi
done
if [ "$pre_ok" -eq 1 ]; then
    if grep -R -n "NPY_ARRAY_UPDATEIFCOPY" /app/hexcore >/dev/null 2>&1; then
        echo "stale removed numpy C API flag NPY_ARRAY_UPDATEIFCOPY still referenced" >&2
        pre_ok=0
    fi
fi
# ---- no-tamper: bundled visible test suite must be byte-identical
if [ "$pre_ok" -eq 1 ]; then
    suite_sha="$(sha256sum /app/hexcore/tests/test_hexcore.py 2>/dev/null | awk '{print $1}')"
    if [ "$suite_sha" != "56bc933d333b62a99730758c4f3fc0b978f9ee75c7bd9ed81eaf937dd256da65" ]; then
        echo "tests/test_hexcore.py was modified or is missing" >&2
        pre_ok=0
    fi
fi

python3 - "$pre_ok" <<'PY'
import json, os, subprocess, sys

failures = []
if int(sys.argv[1]) != 1:
    failures.append("pre-checks failed (deliverables / stale flag / tampered suite)")

def sh(args, timeout):
    return subprocess.run(args, capture_output=True, text=True,
                          timeout=timeout, cwd="/tmp")

# ---- numpy 2.x must be the active runtime
try:
    r = sh([sys.executable, "-c", "import numpy; print(numpy.__version__)"], 60)
    if r.returncode != 0 or not r.stdout.strip().startswith("2."):
        failures.append("numpy 2.x not active: %s%s" % (r.stdout[-200:], r.stderr[-200:]))
except Exception as e:
    failures.append("numpy check crashed: %r" % (e,))

# ---- rebuild + reinstall from the repaired tree (executes setup.py)
if not failures:
    try:
        r = sh([sys.executable, "-m", "pip", "install", "--no-build-isolation",
                "--no-deps", "--force-reinstall", "--quiet", "/app/hexcore"], 240)
        if r.returncode != 0:
            failures.append("rebuild/install from /app/hexcore failed:\n" +
                            (r.stderr or r.stdout)[-1500:])
    except Exception as e:
        failures.append("rebuild crashed: %r" % (e,))

# ---- visible pytest suite must pass against the freshly built package
if not failures:
    try:
        r = sh([sys.executable, "-m", "pytest", "-q", "/app/hexcore/./tests"], 120)
        if r.returncode != 0:
            failures.append("visible pytest suite failed:\n" + r.stdout[-1500:])
    except Exception as e:
        failures.append("pytest crashed: %r" % (e,))

# ---- probe battery (hidden cases execute the installed extension)
PROBE = r'''
import json, sys
import numpy as np
import hexcore

def eq(got, want):
    def f(x):
        if isinstance(x, list):
            return [f(i) for i in x]
        return round(float(x), 7)
    return f(got) == f(want)

case = json.load(open(sys.argv[1]))
errs = []
for name, args, expect in case.get("pure", []):
    fn = getattr(hexcore, name, None)
    if fn is None or not callable(fn):
        errs.append("no function %s" % name)
        continue
    try:
        got = fn(*args)
    except Exception as e:
        errs.append("%s raised %r" % (name, e))
        continue
    if not eq(got, expect):
        errs.append("%s got %r want %r" % (name, got, expect))
for c in case.get("clamps", []):
    b = np.array(c["base"], dtype=np.float64).reshape(c["shape"])
    kind = c.get("view")
    if kind == "T":
        t = b.T
    elif kind == "cols":
        t = b[:, ::2]
    elif kind == "F":
        b = np.asfortranarray(b)
        t = b
    else:
        t = b
    try:
        if c.get("lo") is None and c.get("hi") is None:
            hexcore.clamp_inplace(t)
        else:
            hexcore.clamp_inplace(t, c["lo"], c["hi"])
    except Exception as e:
        errs.append("clamp_inplace raised %r" % (e,))
        continue
    if not eq(t, c["expect_view"]):
        errs.append("clamp view got %r want %r" % (t.tolist(), c["expect_view"]))
    if "expect_base" in c and not eq(b, c["expect_base"]):
        errs.append("clamp base got %r want %r" % (b.tolist(), c["expect_base"]))
print("PROBE_OK" if not errs else "PROBE_FAIL: " + "; ".join(errs))
sys.exit(0 if not errs else 3)
'''

if not failures:
    hidden = "/tests/hidden"
    cases = sorted(os.listdir(hidden)) if os.path.isdir(hidden) else []
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        path = os.path.join(hidden, c, "case.json")
        if not os.path.isfile(path):
            failures.append("hidden case '%s' malformed" % c)
            continue
        try:
            r = sh([sys.executable, "-c", PROBE, path], 120)
            if r.returncode != 0:
                failures.append("hidden case '%s': %s" % (c, (r.stdout or r.stderr).strip()[-500:]))
        except Exception as e:
            failures.append("hidden case '%s' crashed: %r" % (c, e))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
