#!/bin/bash
# Oracle for plimsoll-bell: repairs scipy's kstest string-null-with-args bug
# inside the pinned checkout at /app/src, byte-identically to the upstream
# fix for gh-25448, and writes the failing-reproduction deliverable
# /app/reproduce.py. It NEVER reads /tests.
set -euo pipefail

SRC=/app/src

# 1) Apply the fix: in _parse_kstest_args, resolve string distribution names
#    through the full distribution class hierarchy so the CDF accepts the
#    loc/scale parameters passed via args=, instead of the special-case
#    {'norm': special.ndtr} mapping whose CDF cannot take them.
#    fix_scipy.py anchors the edit on the pinned parent bytes and fails
#    loudly if the checkout ever drifts.
python3 /solution/fix_scipy.py

# 2) Write the failing-reproduction deliverable: a self-contained script that
#    imports scipy from whatever checkout it is handed, computes the one-sample
#    KS statistic with the null given as the string name "norm" + fitted args
#    and as the equivalent callable CDF + args, prints both plus the scipy
#    path, and exits 0 iff both statistics agree within 1e-10. On the
#    original buggy checkout the string form raises the ndtr TypeError and
#    the script exits 1; on the repaired checkout it exits 0.
cat > /app/reproduce.py <<'PY'
#!/usr/bin/env python3
"""Failing reproduction for scipy's kstest string-null-with-args bug.

Contract (plimsoll-bell):
  python3 reproduce.py [checkout-dir]
    - imports scipy from <checkout-dir> (the checkout's own package);
    - draws a deterministic sample, fits a Normal distribution, then computes
      the one-sample KS statistic twice with the checkout's own scipy:
        * CALLABLE_STATISTIC: null as a callable CDF (+ fitted args via args=)
        * STRING_STATISTIC:   null as the string name "norm" (+ same args)
    - prints exactly three lines:
        SCIPY: <path of the imported scipy/__init__.py>
        CALLABLE_STATISTIC: <value>
        STRING_STATISTIC: <value>
    - exits 0 iff both statistics were computed and
      |got - ref| / |ref| < 1e-10; else exits 1 (including when the string
      form raises an exception, whose text is printed to stderr).
On the original buggy checkout the string form raises
TypeError: ndtr() takes from 1 to 2 positional arguments but 3 were given
and this script exits 1; on a corrected scipy it exits 0.
"""
import sys

CHECKOUT = sys.argv[1] if len(sys.argv) > 1 else "/app/src"
sys.path.insert(0, CHECKOUT)

import numpy as np  # noqa: E402

import scipy  # noqa: E402
import scipy.stats as stats  # noqa: E402
from scipy.special import ndtr  # noqa: E402

rng = np.random.default_rng(254482544825448)
x = rng.normal(size=100)
loc, scale = stats.norm.fit(x)

ref = stats.kstest(x, lambda t, u, s: ndtr((t - u) / s), args=(loc, scale)).statistic
try:
    got = stats.kstest(x, "norm", args=(loc, scale)).statistic
except TypeError:
    print(f"SCIPY: {scipy.__file__}", flush=True)
    print(f"CALLABLE_STATISTIC: {ref}", flush=True)
    print("STRING_STATISTIC: <computation raised>", flush=True)
    raise

print(f"SCIPY: {scipy.__file__}", flush=True)
print(f"CALLABLE_STATISTIC: {ref}", flush=True)
print(f"STRING_STATISTIC: {got}", flush=True)

ok = abs(got - ref) / abs(ref) < 1e-10
sys.exit(0 if ok else 1)
PY
chmod +x /app/reproduce.py

# 3) Prove the reproduction is a genuine failing repro in both directions:
#    materialise the pristine parent tree exactly like the verifier will
#    (git archive of HEAD + meson-python's own install plan + parent bytes
#    for every tracked .py under scipy/), run the repro on it (must FAIL
#    with the ndtr TypeError), and run the repro on the repaired tree (must
#    PASS).
rm -rf /tmp/psb-oracle-pristine
mkdir -p /tmp/psb-oracle-pristine
python3 /solution/materialize.py /tmp/psb-oracle-pristine

if MESONPY_EDITABLE_SKIP=/tmp/sci-build python3 /app/reproduce.py /tmp/psb-oracle-pristine \
   >/tmp/psb-pp.out 2>/tmp/psb-pp.err; then
    echo "ERROR: reproduction passed on the pristine buggy tree" >&2
    exit 1
fi
if ! grep -qs "ndtr" /tmp/psb-pp.err /tmp/psb-pp.out; then
    echo "ERROR: pristine failure did not show the ndtr TypeError" >&2
    sed -n '1,20p' /tmp/psb-pp.err >&2 || true
    exit 1
fi
if ! python3 /app/reproduce.py "$SRC" >/tmp/psb-ok.out 2>/tmp/psb-ok.err; then
    echo "ERROR: reproduction failed on the repaired tree" >&2
    tail -20 /tmp/psb-ok.err >&2 || true
    exit 1
fi
grep -E "^(SCIPY|CALLABLE_STATISTIC|STRING_STATISTIC)" /tmp/psb-ok.out
rm -rf /tmp/psb-oracle-pristine

# 4) The project's own regression test for this bug (extracted from the fix
#    commit into /opt/golden) and a slice of the existing unit suite that
#    covers the same code area must both pass.
cd "$SRC"
python3 -m pytest -q -o addopts= -o filterwarnings=ignore -p no:cacheprovider \
    /opt/golden/test_gh25448.py
cd "$SRC"/scipy/stats
python3 -m pytest -q -o addopts= -o filterwarnings=ignore -p no:cacheprovider \
    tests/test_stats.py -k "TestKSTest or TestKSOneSample"

echo "plimsoll-bell oracle done"