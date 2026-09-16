#!/bin/bash
# Oracle for crance-bell: applies the one-line upstream fix to the real
# scipy tree at /app/src (the exact Wilcoxon survival function must select
# the small-tail formula when k > mean, not when k <= mean), writes the
# reproduction deliverable /app/reproduce.py, then proves the work with the
# project's own test tooling: the project's own TestWilcoxon class and inline
# checks of the same code path (golden regression input plus hidden-style
# inputs). Reads only /app and /solution, never /tests.
# The oracle's own verification runs after the fix: the project's TestWilcoxon
# class and inline checks.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied upstream wilcoxon tail-selection fix"

cat > /app/reproduce.py <<'PY'
#!/usr/bin/env python3
"""Reproduction for the exact-Wilcoxon zero-p-value bug.

For strongly one-sided samples, stats.wilcoxon(x, method='exact') reported a
p-value of exactly 0.0 although the true probability is tiny but nonzero.
This script exits 0 only when the p-value comes out strictly positive and
plausibly sized; while the bug is present it exits non-zero.
"""
import numpy as np
from scipy import stats

def main():
    # strongly one-sided sample: 79 small positives, one negative
    x = np.array(list(range(1, 80)) + [-9], dtype=np.float64)
    res = stats.wilcoxon(x, method="exact")
    p = float(res.pvalue)
    print(f"exact p-value: {p!r}")
    assert p > 0.0, "p-value is exactly zero: impossible event reported"
    # sanity: massively one-sided samples have tiny (but nonzero) p-values;
    # anything close to 1 (or negative) would prove the tail is wrong too
    assert 0.0 < p < 1e-10, f"p-value {p!r} is not a tiny nonzero probability"
    print("ok: exact p-value is tiny but strictly positive")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
PY
chmod +x /app/reproduce.py

echo "oracle: reproduction written to /app/reproduce.py"
python3 /app/reproduce.py || { echo "oracle: reproduction fails on the fixed tree" >&2; exit 1; }

# proof with the project's own tooling
export PYTHONDONTWRITEBYTECODE=1
(cd /app/src/scipy/stats && python3 -m pytest -o addopts="" -p no:cacheprovider \
    "tests/test_morestats.py::TestWilcoxon" -q) || {
        echo "oracle: project's own TestWilcoxon suite failed" >&2; exit 1; }

# the upstream regression input for this exact bug, checked inline (the test
# itself lives at tests/golden/ and is only mounted when the verifier runs)
python3 - <<'PY' || { echo "oracle: golden-input check failed" >&2; exit 1; }
import numpy as np
from scipy import stats

neg = np.array([-98.0, -68.0, -60.0, -56.0, -39.0, -34.0, -9.0, -2.0])
pos = np.array(
    [v for v in range(1, 101) if v not in (2, 9, 34, 39, 56, 60, 68, 98)],
    dtype=np.float64)
x = np.concatenate([pos, neg])
ref = 8.12511917099255e-17
p = float(stats.wilcoxon(x, method="exact").pvalue)
assert p > 0.0, p
assert abs(p - ref) / ref < 1e-12, (p, ref)
print(f"oracle: upstream regression input pvalue {p!r} matches reference")
PY

# inline checks equivalent to the hidden cases (same code path, inputs the
# upstream regression test does not use)
python3 - <<'PY' || { echo "oracle: inline hidden-style checks failed" >&2; exit 1; }
import numpy as np
from scipy import stats

cases = [
    (np.array(list(range(1, 70)) + [-3], dtype=float), 1.1858461261560205e-20),
    (np.array(list(range(1, 60)) + [-5], dtype=float), 2.42861286636753e-17),
    (np.array(list(range(1, 60)) + [60, 60, 61, 61, -1, -1], dtype=float),
     3.7947076036992655e-19),
]
for x, ref in cases:
    p = float(stats.wilcoxon(x, method="exact").pvalue)
    assert p > 0.0, p
    assert abs(p - ref) / ref < 1e-6, (p, ref)
print("oracle: inline hidden-style checks passed")
PY

echo "oracle: crance-bell solver finished"
exit 0