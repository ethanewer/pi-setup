# Ellipse fitting claims success with too few points

## Situation

`/app/src` is a shallow, pinned clone of the scikit-image repository
(`https://github.com/scikit-image/scikit-image`) at upstream commit
`fff7deabe28fb6039c26588f751e9cad88354f19`, checked out in detached HEAD. The
project is already installed from that checkout in editable mode, so
`import skimage` resolves to `/app/src/skimage` and any edit you make under
`/app/src/skimage` is live immediately — no reinstall, no compilation step.
Python 3.12 and numpy 2.1.3 / scipy 1.14.1 are installed.

There is **no network** at trial time: `git fetch`, `curl` and any other
network use will fail.

The project keeps its unit tests under `/app/src/skimage` and runs them with
pytest. For this task the relevant suite is
`/app/src/skimage/measure/tests/test_fit.py`, which is offline and can be run
as a whole (it also runs in a few seconds):

```
cd /app/src && python3 -m pytest skimage/measure/tests/test_fit.py -o addopts= -p no:cacheprovider -q
```

## The bug

`skimage.measure.EllipseModel` estimates a 2D ellipse from `(x, y)` data
points. An ellipse is determined by **five** parameters — centre `(xc, yc)`,
semi-axes `a` and `b`, and rotation `theta` — so a fit is only determined when
at least five points are supplied. The current implementation has no such
check, and the user gets no usable feedback when too few points are given.
Two distinct symptoms:

1. **Four points: a fabricated result.** With exactly four arbitrary points
   (fewer than the five needed), the fit routine *claims success* and fills in
   meaningless, made-up ellipse parameters. Run:

   ```
   cd /app/src && python3 -c "import numpy as np; from skimage.measure import EllipseModel; m = EllipseModel(); print(m.estimate(np.array([[0., 0.], [1., 2.], [3., 1.], [4., 5.]])))"
   ```

   Right now this prints `True`, and afterwards `m.params` holds a tuple of
   numbers that correspond to no reasonable ellipse through those points.

2. **Three collinear points: a silent failure.** With as few as three points
   the fit reports failure without any explanation of why:

   ```
   cd /app/src && python3 -c "import numpy as np; from skimage.measure import EllipseModel; m = EllipseModel(); print(m.estimate(np.array([[50., 80.], [51., 81.], [52., 80.]])))"
   ```

   This prints `False`, and no warning, error or other diagnostic is emitted.
   A caller cannot tell a degenerate input from a genuine numerical failure.

## What to do

Fix the ellipse fitting so that it refuses to proceed whenever **fewer than
five data points** are supplied, and clearly warns why.

The intended behaviour (the project's own regression test, which the verifier
will run against your tree, asserts the exact warning text below):

- When a fit is attempted with 1–4 data points, `estimate(...)` emits a
  `RuntimeWarning` whose message contains exactly
  `Need at least 5 data points to estimate an ellipse.` and returns `False`,
  without fabricating any parameters (`model.params` stays unset).
- That warning is the *only* diagnostic for such inputs: no other warning or
  exception should accompany it.
- Behaviour with **five or more** points must be unchanged, including for
  degenerate inputs that legitimately fail for other reasons (for example six
  identical points must still fail with the existing "Standard deviation of
  data is too small..." warning, not yours). A genuine ellipse sampled at
  five or more points must still fit successfully with the true parameters.

After your change, the first repro above must print `False` (with the warning
on stderr), and the second repro must print `False` **and** emit the warning.

Verify with the project's own suite:

```
cd /app/src && python3 -m pytest skimage/measure/tests/test_fit.py -o addopts= -p no:cacheprovider -q
```

Run it **before** your change: it should be fully green. Run it again **after**
your change: exactly one test, `test_ellipse_model_estimate_failers`, will
fail — that is expected and is a signal you are on the right track. That
checked-out test still asserts the *old* contract: its last line passes three
collinear points to `estimate` and expects a bare `False` with no warning. A
correct fix intentionally makes that assertion fail, because the new warning
you emit escapes its unupdated expectations and the project's pytest config
(`filterwarnings = ["error", ...]` in `pyproject.toml`) turns unhandled
warnings into errors. Upstream updated that same test in the same change as
the fix, and the verifier runs the project's updated test file instead. Do
**not** modify or update any test file: every test *other than* that one
outdated case must remain green after your change, exactly as it was before.

## Constraints

The deliverable is the repository at `/app/src`: modify the code there until
the behaviour above holds. Do not change the git metadata of the checkout (no
new commits, no rebasing, no checking out other revisions, no fetching): the
tree must remain the same clone of the same revision, with only your code fix
applied to the working tree. Do not modify the project's own test files, and
do not touch anything under `/solution` or `/tests`: those belong to the
verifier, which will run its own checks against your fixed tree.