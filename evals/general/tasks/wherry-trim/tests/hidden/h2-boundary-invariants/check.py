#!/usr/bin/env python3
"""Hidden case h2: boundary invariants of the max-trials budget.

Checks that (a) the probability==0 shortcut still returns 0 and the
n_inliers==0 case still returns inf (a repair that deletes or bypasses the
shortcuts breaks this), (b) for ordinary inputs the budget still equals the
independently computed log formula exactly (a repair that clamps the final
result or hardcodes values breaks this), and (c) tiny probabilities the
upstream test does not use yield exactly 1 (the pre-fix code returns -0.0).

Fails on the pristine pre-fix package (the 2e-20 / 1e-45 probes return -0.0);
passes on a repaired package.
"""
import sys

import numpy as np

from skimage.measure.fit import _dynamic_max_trials as budget

failures = []

# (a) boundary semantics that must be preserved
r = budget(5, 100, 3, 0.0)
if not (r == 0 and float(r) == 0.0):
    failures.append(("probability==0 shortcut", (5, 100, 3, 0.0), repr(r)))
r = budget(0, 100, 3, 0.5)
if not np.isinf(r):
    failures.append(("n_inliers==0 infinity", (0, 100, 3, 0.5), repr(r)))
r = budget(0, 100, 3, 0.0)
if not (r == 0 and float(r) == 0.0):
    failures.append(("probability==0 takes precedence", (0, 100, 3, 0.0), repr(r)))

# (b) exact agreement with the independent log formula on ordinary inputs
for ni, ns, ms, p in [(60, 100, 8, 0.999), (30, 100, 15, 0.98), (80, 1000, 6, 0.995)]:
    ratio = ni / ns
    denom = 1.0 - ratio ** ms
    nom = 1.0 - p
    expected = int(np.ceil(np.log(nom) / np.log(denom)))
    got = int(float(budget(ni, ns, ms, p)))
    if got != expected:
        failures.append(("exact-formula", (ni, ns, ms, p), (expected, got)))

# (c) tiny probabilities not used by the upstream test
r = budget(3, 100, 4, 2e-20)
if not (np.isfinite(r) and float(r) > 0 and int(float(r)) == 1):
    failures.append(("tiny", (3, 100, 4, 2e-20), repr(r)))
r = budget(1, 100, 1000, 1e-45)
if not (np.isfinite(r) and float(r) > 0 and int(float(r)) == 1):
    failures.append(("tiny", (1, 100, 1000, 1e-45), repr(r)))

if not failures:
    print("h2 PASS: boundary shortcuts, exact-formula agreement and tiny-probability budgets all hold")
    sys.exit(0)

print("h2 FAIL: %d check(s) failed" % len(failures))
for kind, args, got in failures:
    print("  kind=%s inputs=%r -> %r" % (kind, args, got))
sys.exit(1)