# scipy.optimize.minimize silently rewrites the caller's bounds object

## Situation

`/app/src` is a shallow clone of the SciPy repository
(`https://github.com/scipy/scipy`) at the pinned upstream commit
`68942fb357ee133e75709e91959d322325fffb90`, checked out in detached HEAD. The
library is already compiled and installed from that checkout in **editable**
mode: `import scipy` resolves to `/app/src/scipy`, and any edit you make to a
plain-Python file under `/app/src/scipy` is live immediately — no rebuild, no
reinstall step.

There is **no network** at trial time: `git fetch`, `curl`, `pip install`
and any other network use will fail.

The project's own unit tests live under `/app/src/scipy/optimize/tests` and
run with pytest (`cd /app/src && python3 -m pytest ...`). Only run targeted
tests; SciPy's pytest configuration turns warnings into errors and some tests
are slow.

## The bug

A caller can construct a *dimension-agnostic* bounds object from scalar
limits, meaning one object that is valid for an optimization problem of any
number of variables:

```python
from scipy import optimize
bounds = optimize.Bounds(0., np.inf)   # lower limit 0, upper limit infinity for EVERY variable
```

`optimize.minimize(...)` accepts such an object for a problem of any size. But
passing it in **silently rewrites the object in place**: by the time `minimize`
returns, the scalar limits on the *caller's* object have been replaced with
arrays broadcast to the size of the current optimization problem, and the
object's per-variable state (including the flag recording whether bounds may
be violated) is left tied to the first call it was ever used for.

That mutation has two user-visible consequences:

- **Reuse breaks.** A caller who creates one dimension-agnostic bounds object
  and reuses it for problems of different sizes gets corrupted limits from the
  second call onward — the second call can fail outright or run with stale
  shapes.
- **Inspection lies.** Any code that reads the object afterwards — its `.lb`
  and `.ub` attributes, its `repr()` — sees data the caller never assigned.

Here is a reproduction; on this image it currently fails:

```python
python3 - <<'EOF'
import numpy as np
from scipy import optimize
bounds = optimize.Bounds(0., np.inf)
lb, ub = bounds.lb, bounds.ub
optimize.minimize(optimize.rosen, [0.5, 0.5], method='trust-constr', bounds=bounds)
assert bounds.lb is lb and bounds.ub is ub, 'mutated'
EOF
```

The `assert` raises: the caller's object has been rewritten.

## What to do

Fix the library in the checked-out tree at `/app/src` so that:

- Function optimization with bounds (`optimize.minimize`) never modifies the
  caller's bounds object — no matter which solver method is used (`nelder-mead`,
  `powell`, `l-bfgs-b`, `tnc`, `slsqp`, `cobyla`, `cobyqa`, `trust-constr`, ...)
  and no matter how many variables the problem has. The object the caller
  passed must keep exactly the attributes and values the caller set.
- A dimension-agnostic bounds object built from scalar limits stays usable
  across problems of different sizes, and remains dimension-agnostic (still
  scalar limits) *after* being used.
- The reproduction above exits 0.
- The project's own existing optimization tests keep passing. For example:

  ```
  cd /app/src && python3 -m pytest \
    scipy/optimize/tests/test_optimize.py::test_bounds_with_list \
    scipy/optimize/tests/test_optimize.py::test_all_bounds_equal \
    scipy/optimize/tests/test_optimize.py::test_all_bounds_equal_writable \
    -q
  ```

  (Pick the node ids you consider relevant — the point is to exercise the
  project's own tests, not to invent new ones.)

Write a short root-cause note to `/app/explanation.md`: what contract the
caller relies on, where in the library the caller's object gets rewritten, and
the minimal change you made. A few sentences are enough.

Do not change the git metadata of the checkout (no new commits, no rebasing,
no `git checkout` of other revisions): the tree must remain the same clone of
the same revision, with only your code fix applied to the working tree. And do
not touch anything under `/solution` or `/tests`: those belong to the
verifier, which runs its own checks against your fixed tree. The deliverables
are the fixed repository at `/app/src` and the note at `/app/explanation.md`.