# The statistical summary routine raises on an empty (zero-row) data frame

## Situation

`/app/src` is a shallow, pinned clone of the statsmodels repository
(`https://github.com/statsmodels/statsmodels`) at upstream commit
`52f10d214d4dc02e9b521b9f9a83c5e3d4880f94`, checked out in detached HEAD.
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
`/app/src`). Test the **installed** package instead:

```
rm -rf /tmp/smtest && mkdir -p /tmp/smtest
cp /app/src/statsmodels/stats/tests/test_descriptivestats.py /tmp/smtest/
cd /tmp/smtest && python3 -m pytest test_descriptivestats.py -q
```

## The bug

The project's descriptive-statistics routine `statsmodels.stats.descriptivestats.describe`
computes a table of statistics (counts, means, standard deviations, modes,
skewness, kurtosis, Jarque-Bera ...) for each column of a data frame, and its
class counterpart `Description` builds the same table.

Given a data frame with **zero rows** — an empty table that still carries
columns — the routine raises an unhelpful exception instead of returning a
summary:

- a frame whose columns are numeric fails with `ValueError: Length of values
  (2) does not match length of index (1)`, thrown from deep inside pandas'
  column-apply machinery;
- a frame whose column is categorical fails with `KeyError: 2`, raised when
  the routine tries to report skewness/kurtosis computed on an empty result.

Both exceptions abort a report on data that is harmless: an empty input with
declared columns is a legitimate, common case (e.g. the result of filtering a
frame down to nothing). The routine should instead return a summary in which:

- every per-column count row says 0 observations and 0 missing values
  (`nobs` and `missing` rows);
- every numerical statistic (mean, std, skew, kurtosis, mode, Jarque-Bera,
  median, ...) is NaN for each column;
- the result is a frame with exactly the input's columns, and it matches what
  the underlying data library itself produces for the same input.

You can reproduce it with:

```
cd /tmp && python3 - <<'EOF'
import pandas as pd
from statsmodels.stats.descriptivestats import describe

df = pd.DataFrame({"a": pd.Series([], dtype="float64")})
print(describe(df))
EOF
```

The repository's own test module for this routine already contains a failing
parametrized case — `test_empty_rows` — covering a single numeric column, a
single categorical column, and a mixed frame. Take the tests in the tree as
authoritative.

## What you need to do

Fix the routine in the checked-out tree at `/app/src` so that `describe` (and
`Description`) return a proper empty/NaN summary for zero-row input instead of
raising, while everything that currently works keeps working: non-empty frames
must produce exactly the same statistics they do today, and malformed inputs
the routine is supposed to reject must still be rejected.

Unwrap the traceback, find where the undefined quantities are computed for an
empty frame, and make those computations yield NaN in the empty case. The
project's own tests (run as shown above, against the installed package) are
your spec: `test_empty_rows` must pass, and so must every other test in that
module. Verify your change by rebuilding and reinstalling from the repaired
tree and re-running the suite.

## Constraints

- Network is unavailable; everything needed (toolchain, pinned dependencies,
  repository, build directory) is already in the image. `/opt/sm-build` may be
  reused freely but do not delete or wipe it.
- The clone at `/app/src` is the deliverable. Fix the bug in place only: do
  not rewrite history, do not fetch or add remotes, do not commit or stage,
  and do not touch build or packaging files (`pyproject.toml`, `meson.build`,
  the `meson.build` trees under `statsmodels/`, or the dependency pins).
- Do not modify or remove anything under `statsmodels/stats/tests/`: the test
  module there is part of the image exactly as the release intended it, and
  the verifier keeps it byte-identical to its golden copy. Do not add, delete
  or rename any file in the repository — change only the library source the
  fix requires.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. The tree is still at the pinned commit: exactly one commit reachable, no
   fetched history, the upstream fix commit absent from the object store, and
   the only working-tree difference from the shipped state is the library
   source change that fixes the bug (nothing deleted, nothing added, no test
   or packaging file modified).
2. The project's own `test_descriptivestats.py` test module — rebuilt and
   reinstalled from your repaired tree — passes end to end, including the
   upstream `test_empty_rows` regression cases.
3. Hidden cases: additional zero-row inputs the upstream test does not use
   (multi-column numeric frames, a zero-row `Series` input, nullable integer
   columns, explicit statistics selections, categorical top/freq on an empty
   mixed frame, confidence-interval bounds) must all return correct NaN/zero
   summaries rather than raising.
4. The reproduction snippet above returns a summary instead of raising.

Deliverable: the repaired `/app/src` tree (the verifier rebuilds and
reinstalls it itself — you do not need to leave a modified site-packages
behind, though doing so is harmless).