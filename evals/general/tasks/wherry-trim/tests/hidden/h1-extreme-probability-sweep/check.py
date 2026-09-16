#!/usr/bin/env python3
"""Hidden case h1: extreme-probability sweep of the max-trials budget.

The upstream regression test probes probabilities 0, 1 and 1e-40 with
min_samples 10 and 1000. This case uses probabilities and min_samples the
upstream test does not use, and requires every budget to be a positive
integer (exactly 1 where the clipped logarithms force it).

Fails on the pristine pre-fix package (the tiny-probability probes return
-0.0); passes on a repaired package.
"""
import sys

import numpy as np

from skimage.measure.fit import _dynamic_max_trials as budget

failures = []

# 1) tiny stopping probabilities across ratios and min_samples: every budget
#    must be exactly the positive integer 1.
tiny = [
    (1, 100, 2, 1e-45),
    (1, 100, 7, 1e-45),
    (1, 100, 37, 1e-45),
    (5, 1000, 10, 1e-45),
    (500, 1000, 100, 1e-45),
    (1, 100, 2, 1e-30),
    (1, 100, 3, 1e-20),
    (5, 200, 4, 1e-17),
]
for ni, ns, ms, p in tiny:
    r = budget(ni, ns, ms, p)
    if not (np.isfinite(r) and float(r) > 0 and float(r) == float(np.ceil(float(r))) and int(float(r)) == 1):
        failures.append(("tiny", (ni, ns, ms, p), repr(r)))

# 2) denominator term rounding to exactly 1 (large min_samples, moderate
#    probability): every budget must still be a positive integer.
near_one_denom = [
    (1, 100, 1000, 0.9999),
    (1, 1000, 800, 0.999999),
    (40, 100, 50, 0.999),
]
for ni, ns, ms, p in near_one_denom:
    r = budget(ni, ns, ms, p)
    if not (np.isfinite(r) and float(r) > 0 and float(r) == float(np.ceil(float(r)))):
        failures.append(("near-one-denom", (ni, ns, ms, p), repr(r)))

if not failures:
    print("h1 PASS: %d tiny-probability probes and %d near-one-denominator probes"
          % (len(tiny), len(near_one_denom)))
    sys.exit(0)

print("h1 FAIL: %d probe(s) violated the positive-integer budget contract" % len(failures))
for kind, args, got in failures:
    print("  kind=%s inputs=%r -> %s" % (kind, args, got))
sys.exit(1)