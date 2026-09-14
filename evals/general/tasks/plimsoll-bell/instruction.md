# scipy: one-sample Kolmogorov-Smirnov test crashes when the null distribution is given by name plus parameters

## Environment

- A development checkout of the **scipy** source tree is at **`/app/src`**, at
  the exact revision this task was measured against. The package was built
  from source and installed **editably**, so:

  ```bash
  cd /app/src && python3 -c "import scipy; print(scipy.__file__)"
  ```

  prints `/app/src/scipy/__init__.py`, and any edit you make to a `.py` file
  under `/app/src` takes effect immediately — no rebuild, no reinstall. The
  compiled extension modules load from the prebuilt meson directory;
  you will not need to rebuild anything.

- The container has **no network**. Everything is already installed (numpy,
  pytest, hypothesis, pooch, mpmath). Do not try to `pip install`, `git
  fetch`, or download anything.

- To run the project's own tests, for example the one-sample
  Kolmogorov-Smirnov slice:

  ```bash
  cd /app/src && python3 -m pytest -q -o addopts= -o filterwarnings=ignore \
      -p no:cacheprovider scipy/stats/tests/test_stats.py -k "TestKSTest or TestKSOneSample"
  ```

  Focused runs take seconds. The machine is budgeted at one CPU; everything
  you need to do is pure Python.

- The checkout is a git repository at the pinned revision with a clean tree.
  `git status`, `git log`, `git diff`, `git grep` and the test suite are all
  there for you to inspect. Never move the checked-out revision and never
  `git commit`. Keep scratch files under `/tmp`, never inside the repository.

## The bug

scipy's one-sample Kolmogorov-Smirnov goodness-of-fit test
(`scipy.stats.kstest`) accepts the null distribution in several forms: an
array of sample values (two-sample form), a callable CDF, or the *string
name* of a known distribution — for example `"norm"`, `"expon"`, `"gamma"`.
When the null is a distribution that has parameters — location `loc`, scale
`scale`, or shape parameters — the parameters are passed separately through
the `args=` keyword, and the string-name form is supposed to work exactly
like the callable-CDF form: the test uses `distname.cdf(data, *args)`.

A standard workflow does exactly this. Fit a distribution to a sample, then
run the goodness-of-fit test against the fitted distribution, passing its
name and the fitted parameters:

```python
import numpy as np
from scipy import stats

sample = (your data)
loc, scale = stats.norm.fit(sample)
d, p = stats.kstest(sample, "norm", args=(loc, scale))
```

Users expect this to run the test, comparing the sample against the normal
CDF with location `loc` and scale `scale`. On this revision, instead, **the
call raises an exception before the test runs at all**:

```
TypeError: ndtr() takes from 1 to 2 positional arguments but 3 were given
```

Passing the very same null as a *callable* CDF with the same parameters
works fine:

```python
from scipy.special import ndtr
d, p = stats.kstest(sample, lambda t, l, s: ndtr((t - l) / s), args=(loc, scale))
```

so the failure is specific to the string-name form combined with `args=`.
The behaviour you must preserve:

- `stats.kstest(sample, "norm")` with **no** `args` keeps working, and its
  statistic equals `stats.kstest(sample, lambda t: ndtr(t))`;
- other string names with parameters (e.g. `"expon"` with a fitted
  `(loc, scale)`, `"uniform"` with a fitted `(loc, scale)`, `"gamma"` with a
  fitted `(shape, loc, scale)`) keep working and agree with the equivalent
  callable-CDF form;
- a callable CDF with `args=` keeps working.

## What you must deliver

1. **`/app/reproduce.py` — your own failing reproduction, as a deliverable.
   Write this first, before touching any scipy source.** A single-file
   Python script that:

   - takes the path to the scipy checkout as its first command-line argument
     (default `/app/src`);
   - imports scipy **from that checkout** (put the checkout path at the
     front of `sys.path` and then `import scipy`, `import scipy.stats`);
   - draws a deterministic random sample, fits a Normal distribution to it,
     and computes the one-sample KS statistic two ways with the checkout's
     own code:
     * `ref` — the null given as a **callable CDF** with the fitted
       parameters passed through `args=`; and
     * `got` — the null given as the **string name** `"norm"` with the same
       fitted parameters passed through `args=`;
   - prints exactly three lines to stdout:
     ```
     SCIPY: <path of the imported scipy/__init__.py>
     CALLABLE_STATISTIC: <ref>
     STRING_STATISTIC: <got>
     ```
   - exits **0 if and only if** both statistics were computed and
     `abs(got - ref) / abs(ref) < 1e-10`; exits **1 otherwise**, including
     when computing `got` raises an exception (print the exception to
     stderr so a human can see it).

   It will be run twice: once against your repaired tree (as
   `python3 /app/reproduce.py /app/src`), and once against a pristine,
   unmodified copy of the original checkout. **On the pristine buggy tree
   your script must FAIL** (exit 1, showing the `ndtr()` TypeError); **on
   the repaired tree it must PASS** (exit 0). Verify both directions
   yourself before you consider yourself done. The script must be
   self-contained: only the Python standard library plus the checkout's own
   package may be used (your scipy checkout, numpy from the image, nothing
   else).

2. **A fixed scipy.** Make the checkout's own code run the string-name form
   with parameters: for every string distribution name, the null CDF used by
   the one-sample KS test must accept the parameters passed via `args=` the
   same way a callable CDF does, and the resulting statistic (and p-value)
   must agree with the callable-CDF form of the same null to tight
   tolerance. The three preserved behaviours above must all still hold.

   Only scipy source files may be modified, and only the file(s) that
   actually need to change for this behaviour. Do not add, rename or delete
   any other tracked or untracked file in the repository, do not change the
   checked-out revision, and do not touch anything outside `/app/src` (no
   site-packages, no interpreter, no wrappers, no new modules anywhere).

## How it will be checked

The acceptance will then:

1. run **your** `/app/reproduce.py` against the repaired tree (must exit 0)
   and against a pristine copy of the original checkout (must exit 1,
   showing the crash);
2. run the project's own updated regression test for this behaviour (baked
   into the image at `/opt/golden`, extracted from the upstream fix) against
   your tree — it must pass;
3. run a slice of the project's own existing unit test suite covering the
   same code area (`scipy/stats/tests/test_stats.py -k "TestKSTest or
   TestKSOneSample"`) — it must still pass;
4. run additional inputs your reproduction does not cover — they must all
   behave correctly.

Where precisely the string-name resolution happens, which source file owns
it, and how `args` get through to the CDF is **your call** — the source
tree, the test suite and the git history inside `/app/src` are all there for
you to inspect. Write the reproduction first, watch it fail, then fix the
code until it passes.

## Deliverable summary

- `/app/reproduce.py` — your own failing reproduction (see contract above).
- A fixed `/app/src` — the scipy checkout, repaired in place.
- Nothing else. No report file, no new scripts anywhere under `/app/src`.