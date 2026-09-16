#!/usr/bin/env python3
"""Apply the minimal upstream fix for scipy issue #25880.

The bug: `scipy.optimize.minimize` routes every bounds-using method through
`_validate_bounds` in scipy/optimize/_minimize.py, which broadcast the scalar
(``np.atleast_1d``) `lb`/`ub` of the CALLER's `Bounds` object onto the current
problem's shape and stored the broadcast arrays back onto the caller's object:

    bounds.lb = np.broadcast_to(bounds.lb, x0.shape)
    bounds.ub = np.broadcast_to(bounds.ub, x0.shape)

A dimension-agnostic `Bounds(0., np.inf)` passed to a 2-variable problem came
back with `lb == array([0., 0.])` and `ub == array([inf, inf])`: the caller's
object was silently rewritten, reuse across problem sizes broke from the
second call onward, and inspection of the object afterwards showed arrays the
caller never assigned.

The upstream fix (commit b92b297a5a0c372600bffffd4dc83513be9bfd39, two hunks
in scipy/optimize/_minimize.py) makes `_validate_bounds` work on a shallow
copy of the bounds object instead of the caller's object:

    import copy                                   (module top)
    ...
    bounds = copy.copy(bounds)  # don't broadcast onto the caller's object

This file applies exactly those two edits to the working tree at
`scipy/optimize/_minimize.py`.
"""
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

# --- edit 1: make `copy` available at module top -----------------------------
old_import = "__all__ = ['minimize', 'minimize_scalar']\n\n\nfrom warnings import warn\n"
new_import = ("__all__ = ['minimize', 'minimize_scalar']\n\n\n"
              "import copy\n"
              "from warnings import warn\n")
if "import copy\n" not in src:
    assert src.count(old_import) == 1, "import anchor not unique/found"
    src = src.replace(old_import, new_import)

# --- edit 2: validate (and broadcast) a COPY, never the caller's object -------
old_bounds = "    msg = \"The number of bounds is not compatible with the length of `x0`.\"\n    try:\n"
new_bounds = ("    msg = \"The number of bounds is not compatible with the length of `x0`.\"\n"
              "    bounds = copy.copy(bounds)  # don't broadcast onto the caller's object\n"
              "    try:\n")
if "bounds = copy.copy(bounds)  # don't broadcast onto the caller's object\n" not in src:
    assert src.count(old_bounds) == 1, "validate_bounds anchor not unique/found"
    src = src.replace(old_bounds, new_bounds)

open(path, "w", encoding="utf-8").write(src)
print("patched", path)