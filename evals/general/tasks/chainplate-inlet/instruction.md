# The mixed-effects model report ignores the title you give it

## Situation

`/app/src` is a shallow, pinned clone of the statsmodels repository
(`https://github.com/statsmodels/statsmodels`) at upstream commit
`3c102982fecc91782d7836b9ae456fe869dd3578`, checked out in detached HEAD.
**There is no network at trial time**: `git fetch`, `curl` and any other
network use will fail.

Python 3.12 is installed with numpy 2.5.3, scipy 1.18.1, pandas 3.0.5, patsy
1.0.3 and formulaic 1.2.2. The statsmodels in this tree has been *built from
the checkout and installed* into site-packages. The package installs from the
tree like this (fast once the tree has been built, because the meson build
directory at `/opt/sm-build` is reused — a fresh edit to one pure-Python file
reinstalls in seconds):

```
cd /app/src
pip install --no-build-isolation --no-deps --no-cache-dir --disable-pip-version-check --config-settings=builddir=/opt/sm-build .
```

One environment quirk you must work around: the source tree at `/app/src` is
**not importable by itself** — the generated `statsmodels/_version.py` is
produced into the installed build, not into the source tree. So never run
Python or pytest with `/app/src` on the import path (in particular, do not run
them with `/app/src` as the working directory or point pytest at a file under
`/app/src`). Test the **installed** package instead. The project's own test
module for the mixed-effects model lives at
`statsmodels/regression/tests/test_lme.py` in the tree; it loads shared
fixtures from the sibling `results/` directory and uses one relative import,
so it needs a small package-shaped scratch directory to run standalone:

```
rm -rf /tmp/smtest && mkdir -p /tmp/smtest/regression_tests
cp  /app/src/statsmodels/regression/tests/test_lme.py /tmp/smtest/regression_tests/
cp  /app/src/statsmodels/regression/tests/__init__.py /tmp/smtest/regression_tests/__init__.py
cp -r /app/src/statsmodels/regression/tests/results /tmp/smtest/regression_tests/
cd /tmp/smtest && python3 -m pytest -q regression_tests/test_lme.py
```

That whole module is green at this checkout; use it as your spec.

## The bug

The linear mixed-effects model (`statsmodels.regression.mixed_linear_model.MixedLM`)
fits fine, and its results object can render a tabular report of the fit via
the report method's `title` argument — which the method's own documentation
says "replaces the default title". It does not. Whatever string you pass is
silently dropped and the report is always headed with the same default
heading:

```
$ python3 /app/probe_title.py
requested title: Custom MixedLM Summary
returned title : Mixed Linear Model Regression Results
title with no argument: Mixed Linear Model Regression Results
BUG PRESENT: the reported title argument was ignored and the default
heading was printed instead
```

Anyone who labels a stack of reports with distinct titles to embed in a
document gets the same default heading for every one of them, with no error
and no warning — the parameter looks like it works while actually doing
nothing. (The probe script exits 1 while the bug is present and 0 once the
title is honored; the default heading is correct behaviour for the no-argument
case.)

You can reproduce it directly with:

```
cd /tmp && python3 - <<'EOF'
import numpy as np
import pandas as pd
from statsmodels.regression.mixed_linear_model import MixedLM

pid = np.repeat([0, 1], 5)
x0 = np.repeat([1], 10)
x1 = [1, 5, 7, 3, 5, 1, 2, 6, 9, 8]
x2 = [6, 2, 1, 0, 1, 4, 3, 8, 2, 1]
y = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
df = pd.DataFrame({"y": y, "pid": pid, "x0": x0, "x1": x1, "x2": x2})
endog = df["y"].values
exog = df[["x0", "x1", "x2"]].values
groups = df["pid"].values
res = MixedLM(endog, exog, groups=groups).fit()
print("returned title:", repr(res.summary(title="Custom MixedLM Summary").title))
assert res.summary(title="Custom MixedLM Summary").title == "Custom MixedLM Summary"
EOF
```

The assertion is the failure: it raises because the returned title is the
default heading, not the one requested.

## What you need to do

Fix the summary-report path of the mixed-model results object in the checked-
out tree at `/app/src` so the report method honors the `title` argument it
documents:

- `res.summary(title="...")` must return a report whose title is exactly the
  string that was passed (whitespace, punctuation and all);
- `res.summary()` and `res.summary(title=None)` must keep producing the
  default heading "Mixed Linear Model Regression Results";
- every other argument of the report method (`yname`, `xname_fe`,
  `xname_re`, `alpha`) and every other test in the project's own module must
  keep working exactly as before.

Unwrap the report-construction code, find where the heading is set, and make
the caller's title take effect. Verify your change by rebuilding and
reinstalling from the repaired tree (command above), then re-running the
module from the scratch directory and the reproduction snippet.

## Constraints

- Network is unavailable; everything needed (toolchain, pinned dependencies,
  repository, build directory) is already in the image. `/opt/sm-build` may
  be reused freely but do not delete or wipe it.
- The clone at `/app/src` is the deliverable. Fix the bug in place only: do
  not rewrite history, do not fetch or add remotes, do not commit or stage,
  and do not touch build or packaging files (`pyproject.toml`, `meson.build`,
  the `meson.build` trees under `statsmodels/`, or the dependency pins).
- Do not add, delete or rename any file in the repository — change only the
  library source the fix requires. In particular leave every file under
  `statsmodels/regression/tests/` untouched.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. The tree is still at the pinned commit: exactly one commit reachable, no
   fetched history, the upstream fix commit absent from the object store, and
   the only working-tree difference from the shipped state is the library
   source change that fixes the bug (nothing deleted, nothing added, no test
   or packaging file modified).
2. The project's own `test_lme.py` test module — the copy released with the
   fix, rebuilt and reinstalled from your repaired tree — passes end to end,
   including its regression test for the title argument.
3. Hidden cases: additional title inputs and fit paths the upstream test does
   not use (unequal group sizes with punctuation/whitespace/unicode titles
   and the `title=None` default, regularized fits, and the title combined
   with `yname`/`xname_fe`/`xname_re` including rendered-table checks).
4. The reproduction snippet above returns the requested title instead of
   raising.

Deliverable: the repaired `/app/src` tree (the verifier rebuilds and
reinstalls it itself — you do not need to leave a modified site-packages
behind, though doing so is harmless).