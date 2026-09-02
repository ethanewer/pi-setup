#!/usr/bin/env python3
"""stack_models.py - correct separability-matrix compositing for compound models.

The SEPARABILITY matrix of a model with n_outputs outputs and n_inputs inputs
is an m x n binary matrix S where S[i][k] == 1 iff output i depends on input k.

The compositing rules (used to derive S for a whole compound model from the
separability of its sub-models, WITHOUT sampling/evaluating the model):

  * leaf (a base affine model) is 1-in / 1-out and fully coupled  ->  [[1]]
  * a stacked (blocked/concatenated) model built with `A & B` maps its
    first chunk of inputs through A and its remaining chunk through B,
    so S = block-diagonal(S_A, S_B).
  * a chained (composed) model built with `A | B` feeds A's outputs into B,
    so S = S_B @ S_A (boolean matrix product); an output only couples to an
    input if there EXISTS an intermediate channel connecting them.
  * Mapping((i0, i1, ...)) is an input permutation: output r reads input ir,
    giving a 0/1 selection matrix.

A naive compositing that, say, unions all couplings across a chain, or treats
every input of a stacked model as feeding every output, over-couples and
reports separable models as fully coupled -- exactly the bug we fix here.
"""
import json
import sys

import numpy as np
from astropy.modeling.models import Linear1D, Mapping


def _is_compound(model):
    return hasattr(model, "left") and hasattr(model, "op") and getattr(model, "op", None) is not None


def _leaf_matrix(model):
    if isinstance(model, Mapping):
        idx = list(model._mapping)
        n_in = int(model.n_inputs)
        return [[1 if k == idx[r] else 0 for k in range(n_in)]
                for r in range(len(idx))]
    if isinstance(model, Linear1D):
        return [[1]]
    raise ValueError("unsupported atomic model %r" % (type(model).__name__))


def separability_matrix(model):
    """Return the m x n separability matrix (list of int rows) of `model`."""
    if not _is_compound(model):
        # a base (non-compound) model: Mapping permutations and 1-in/1-out
        # affine leaves both have a directly-derivable leaf matrix.
        return _leaf_matrix(model)

    op = model.op
    left = separability_matrix(model.left)
    right = separability_matrix(model.right)

    if op == "&":
        rows = []
        for row in left:
            rows.append(list(row) + [0] * len(right[0]))
        for row in right:
            rows.append([0] * len(left[0]) + list(row))
        return rows

    if op == "|":
        combined = np.asarray(right, dtype=float) @ np.asarray(left, dtype=float)
        return (combined > 0).astype(int).tolist()

    raise ValueError("unsupported compound operator %r" % (op,))


def main(argv=None):
    ap = __import__("argparse").ArgumentParser()
    ap.add_argument("--out", default=None,
                    help="write the visible sensor-model separability matrix as JSON")
    args = ap.parse_args(argv)

    # The visible deliverable: the stacked three-sensor instrument.
    L = lambda s: Linear1D(s, 0.0)  # noqa: E731
    model = (L(1.0) & L(2.0)) & Mapping((1, 0))
    S = separability_matrix(model)
    if args.out:
        with open(args.out, "w") as f:
            json.dump({"inputs": model.n_inputs, "outputs": model.n_outputs,
                       "separability": S}, f, indent=2)
        print("wrote %s" % args.out)
    else:
        print(json.dumps({"separability": S}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
