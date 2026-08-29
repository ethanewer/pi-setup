#!/usr/bin/env python3
"""Hidden separability-case driver. Builds a variety of nested/stacked/permuted
compound astropy models, computes an independent ground-truth separability
matrix by numerical Jacobian sampling, and asserts /app/stack_models.py
produces the identical 0/1 matrix. A single wrong bit fails the scenario."""
import json
import os
import sys

import numpy as np
from astropy.modeling.models import Linear1D, Mapping

sys.path.insert(0, "/app")
import stack_models  # noqa: E402


def num_sep(model):
    """Independent ground truth: numeric finite-difference Jacobian pattern."""
    n = model.n_inputs
    arr = np.linspace(0.7, 2.3, n) if n > 1 else np.array([1.3])
    y0 = model(*arr) if n > 1 else model(arr[0])
    if not isinstance(y0, (tuple, list)):
        y0 = (y0,)
    y0 = np.asarray(y0, dtype=float)
    R = np.zeros((model.n_outputs, n), dtype=int)
    eps = 1e-3
    for i in range(n):
        xp = list(arr)
        xp[i] += eps
        yp = model(*xp) if n > 1 else model(xp[0])
        if not isinstance(yp, (tuple, list)):
            yp = (yp,)
        yp = np.asarray(yp, dtype=float)
        for o in range(model.n_outputs):
            if abs(yp[o] - y0[o]) > 2e-6:
                R[o, i] = 1
    return R


L = lambda s: Linear1D(s, 0.0)  # noqa: E731

cases = {
    "single_leaf": L(0.7),
    "diag_pair": L(1.0) & L(2.0),
    "nested_blocks": (L(1.0) & L(2.0)) & (L(3.0) & L(4.0)),
    "perm_chain": (L(2.0) & L(-0.5)) | Mapping((1, 0)),
    "rev_three": (L(1.0) & L(2.0) & L(3.0)) | Mapping((2, 1, 0)),
    "block_with_perm": (L(1.0) & L(2.0)) & Mapping((1, 0)),
}

for name, model in cases.items():
    ref = num_sep(model)
    try:
        got = np.asarray(stack_models.separability_matrix(model), dtype=int)
    except Exception as exc:  # noqa: BLE001
        print("FAIL %s raised %r" % (name, exc))
        sys.exit(1)
    if got.shape != ref.shape or not (got == ref).all():
        print("FAIL %s\nexpected %s\ngot      %s" % (name, ref.tolist(), got.tolist()))
        sys.exit(1)

print("OK separability matrices=%d" % len(cases))
