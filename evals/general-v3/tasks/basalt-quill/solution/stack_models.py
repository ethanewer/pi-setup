#!/usr/bin/env python3
"""stack_models.py -- build nested / stacked / blocked compound astropy
models from a JSON spec and compute the correct separability matrix.

Usage:
    python3 stack_models.py <spec.json> -o <out.json>

Spec format (nested expression tree):
    {"op": "cat",  "a": EXPR, "b": EXPR}   # block / concatenate submodels
    {"op": "pipe","a": EXPR, "b": EXPR}   # stack (a applied first, then b)
    leaf EXPR (one of):
        {"leaf":"shift",        "offset": F}
        {"leaf":"scale",        "factor": F}
        {"leaf":"linear",       "slope": F, "intercept": F}
        {"leaf":"mapping",      "n_in": I, "index": [ints]}
        {"leaf":"poly2d",       "degree": I, "coeffs": {"c0_0":F, ...}}
        {"leaf":"rotation",     "angle": F}

Output JSON: {"n_inputs": M, "n_outputs": N, "matrix": [[0/1 x N], ......]}
Entry [i][j] of `matrix` is 1 when output i depends on input j (so the shape
is N-rows by M-columns when M different i/o values are present).
"""
import argparse
import json

import numpy as np


def build_model(expr):
    """Construct an astropy compound model from a JSON spec `expr`."""
    from astropy.modeling import models
    from astropy.modeling.mappings import Mapping

    op = expr.get("op")
    lk = "a" if "a" in expr else "left"
    rk = "b" if "b" in expr else "right"
    if op == "cat":
        return build_model(expr[lk]) & build_model(expr[rk])
    if op == "pipe":
        return build_model(expr[lk]) | build_model(expr[rk])
    leaf = expr["leaf"]
    if leaf == "shift":
        return models.Shift(offset=expr["offset"])
    if leaf == "scale":
        return models.Scale(factor=expr["factor"])
    if leaf == "linear":
        return models.Linear1D(slope=expr["slope"], intercept=expr["intercept"])
    if leaf == "mapping":
        return Mapping(expr["index"], n_inputs=expr["n_in"])
    if leaf == "poly2d":
        from astropy.modeling.models import Polynomial2D
        return Polynomial2D(expr["degree"], **expr["coeffs"])
    if leaf == "rotation":
        from astropy.modeling.models import Rotation2D
        return Rotation2D(expr["angle"])
    raise ValueError("unknown leaf: %r" % leaf)


def separability_matrix(model):
    """Return the (n_outputs, n_inputs) 0/1 separability matrix of `model`.

    Entry [i, j] is 1 when output i depends on input j.
    """
    from astropy.modeling import mappings
    from astropy.modeling.core import CompoundModel, Model

    if model.n_inputs == 1 and model.n_outputs > 1:
        return np.ones((model.n_outputs, model.n_inputs), dtype=int)

    def coord_matrix(m, pos, nout):
        if isinstance(m, mappings.Mapping):
            axes = []
            for idx in m.mapping:
                axis = np.zeros((m.n_inputs,))
                axis[idx % m.n_inputs] = 1
                axes.append(axis)
            cm = np.vstack(axes)
        elif not m.separable:
            cm = np.ones((m.n_outputs, m.n_inputs))
        else:
            cm = np.eye(m.n_inputs)
        mat = np.zeros((nout, m.n_inputs), dtype=int)
        if pos == "left":
            mat[: m.n_outputs, : m.n_inputs] = cm
        else:
            mat[-m.n_outputs:, -m.n_inputs:] = cm
        return mat

    def cstack(left, right):
        lnout = left.n_outputs if isinstance(left, Model) else left.shape[0]
        rnout = right.n_outputs if isinstance(right, Model) else right.shape[0]
        noutp = lnout + rnout
        if isinstance(left, Model):
            cleft = coord_matrix(left, "left", noutp)
        else:
            cleft = np.zeros((noutp, left.shape[1]), dtype=int)
            cleft[: left.shape[0], : left.shape[1]] = left
        if isinstance(right, Model):
            cright = coord_matrix(right, "right", noutp)
        else:
            cright = np.zeros((noutp, right.shape[1]), dtype=int)
            cright[-right.shape[0]:, -right.shape[1]:] = right
        return np.hstack([cleft, cright])

    def cdot(left, right):
        left, right = right, left
        cleft = coord_matrix(left, "left", left.n_outputs) if isinstance(left, Model) else left
        cright = coord_matrix(right, "right", right.n_outputs) if isinstance(right, Model) else right
        return np.dot(cleft, cright)

    def sep(t):
        if isinstance(t, CompoundModel):
            sl = sep(t.left)
            sr = sep(t.right)
            if t.op == "&":
                return cstack(sl, sr)
            if t.op == "|":
                return cdot(sl, sr)
            return np.ones((t.n_outputs, t.n_inputs), dtype=int)
        return coord_matrix(t, "left", t.n_outputs)

    return np.where(sep(model) != 0, True, False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()
    with open(args.spec) as f:
        expr = json.load(f)
    model = build_model(expr)
    m = int(model.n_inputs)
    n = int(model.n_outputs)
    matrix = separability_matrix(model).tolist()
    with open(args.output, "w") as f:
        json.dump({"n_inputs": m, "n_outputs": n, "matrix": matrix}, f)


if __name__ == "__main__":
    main()