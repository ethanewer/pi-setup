#!/usr/bin/env bash
# Oracle for chainplate-ebb: applies the minimal upstream fix for the
# scipy.optimize.minimize Bounds-mutation bug to the checkout at /app/src
# (one new `import copy`, one `bounds = copy.copy(bounds)` line inside
# `_validate_bounds`), then proves the fix with the issue reproduction, the
# project's own regression tests for this bug (golden bytes from the fix
# commit, baked into the image at /opt/golden), and a subset of the project's
# own existing optimization tests.
set -e

python3 /solution/fix_minimize.py /app/src/scipy/optimize/_minimize.py

echo "== issue reproduction: caller's Bounds is never rewritten =="
cd /app/src && python3 - <<'EOF'
import numpy as np
from scipy import optimize
bounds = optimize.Bounds(0., np.inf)
lb, ub = bounds.lb, bounds.ub
optimize.minimize(optimize.rosen, [0.5, 0.5], method='trust-constr', bounds=bounds)
print('lb is lb:', bounds.lb is lb, ' ub is ub:', bounds.ub is ub,
      ' lb:', repr(bounds.lb), ' ub:', repr(bounds.ub))
assert bounds.lb is lb and bounds.ub is ub, 'caller Bounds mutated'
assert lb.shape == (1,) and ub.shape == (1,), 'no longer dimension-agnostic'
print('ok')
EOF

echo "== golden regression tests (fix-commit test_optimize.py, run from /tmp so the tree stays clean) =="
cp /opt/golden/test_optimize.py /tmp/test_optimize_golden.py
cd /app/src && python3 -m pytest \
  "/tmp/test_optimize_golden.py::test_minimize_does_not_mutate_bounds" \
  "/tmp/test_optimize_golden.py::test_minimize_bounds_reusable_across_sizes" \
  -p no:cacheprovider -q

echo "== the project's own existing optimization tests =="
cd /app/src/scipy/optimize \
 && cd tests && python3 -m pytest \
  "test_optimize.py::test_bounds_with_list" \
  "test_optimize.py::test_all_bounds_equal" \
  "test_optimize.py::test_all_bounds_equal_writable" \
  "test_optimize.py::test_minimize_maxiter_noninteger" \
  -p no:cacheprovider -q

echo "== deliverable: root-cause note =="
python3 - <<'EOF'
note = """Root cause

A caller may pass `optimize.Bounds` built from scalar limits (e.g.
`Bounds(0., np.inf)`) to `optimize.minimize`; such a bounds object is
dimension-agnostic and valid for a problem of any size. Every bounds-using
solver method in `minimize` routed through `_validate_bounds`, which prepared
the bounds by broadcasting them onto the current problem's shape and stored
the result back onto `bounds.lb` / `bounds.ub`:

    bounds.lb = np.broadcast_to(bounds.lb, x0.shape)
    bounds.ub = np.broadcast_to(bounds.ub, x0.shape)

That mutation rewrote the CALLER's object in place: after the call the
scalar limits had been replaced with arrays of the problem's size, so a
Bounds object reused for a problem of a different size failed or ran with
stale shapes from the second call onward, and any code inspecting the object
afterwards saw arrays the caller never assigned.

Minimal change

`scipy/optimize/_minimize.py`, two lines (matching the upstream fix):
- `import copy` at the top of the module;
- in `_validate_bounds`, work on a shallow copy of the bounds object first:
  `bounds = copy.copy(bounds)` before the broadcast assignment, so the
  broadcast arrays are stored on the copy and the caller's object is never
  mutated (its .lb/.ub/keep_feasible keep their caller-set values and
  identities).
"""
open('/app/explanation.md', 'w', encoding='utf-8').write(note)
print('wrote /app/explanation.md')
EOF

echo "== oracle: all steps passed =="