#!/bin/bash
# Verifier for chainplate-inlet: an upstream-clone debugging task on
# statsmodels/statsmodels.
#
# Bug (upstream issue #9805): MixedLMResults.summary() documents a title
# argument ("If not None, then this replaces the default title") but calls
# smry.add_title("Mixed Linear Model Regression Results") unconditionally, so
# the caller's title is silently ignored. The agent must fix the real
# checkout at /app/src. The verifier:
#   0. asserts tree provenance: HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, exactly
#      one commit reachable, no deletions/additions/staging, and the ONLY
#      modified tracked source file is the library module that implements
#      the summary path (it must carry a modification);
#   1. rebuilds and reinstalls statsmodels from the repaired tree into the
#      warmed meson build dir (incremental, seconds) and asserts the
#      installed module is byte-identical to the repaired tree's module;
#   2. runs the project's own test module for this feature -- test_lme.py,
#      extracted byte-for-byte from the fix release into /opt/golden with
#      its results package beside it so it runs standalone -- against the
#      installed library: the 30+ existing tests plus the upstream
#      regression test test_summary_title must ALL pass;
#   3. runs three authored hidden cases that exercise the same summary path
#      from inputs the upstream test does not use (unequal group sizes with
#      punctuation/whitespace/unicode title strings and the title=None
#      default, the fit_regularized public path, and title combined with
#      yname/xname_fe/xname_re plus rendered-table and repeat-call checks);
#   4. runs the raw reproduction: summary(title=...) must return the
#      requested title, and summary()/summary(title=None) the default one.
#
# The fix-bytes scratch dir (/opt/fixcheck, which used to carry the upstream
# fix module back-to-back) is removed at the end of the image build; an agent
# must implement the fix itself, not copy shipped bytes.
#
# All library-touching python invocations below run with `-S` (no site/
# sitecustomize/.pth processing) plus PYTHONPATH into the installed package:
# a runtime wrapper planted in sitecustomize.py, a .pth hook or a conftest
# cannot stand in for a real fix of the tree, and the plain installed module
# is exactly what gets tested.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=3c102982fecc91782d7836b9ae456fe869dd3578
FIX_SHA=0a347973915a2a28ec795cb670343c37ab3d0d92
GOLDEN=/opt/golden
SRCMOD="statsmodels/regression/mixed_linear_model.py"

# Installed site-packages for the `-S` (isolated, no sitecustomize) test runs.
SP=$(python3 -c "import site; print(site.getsitepackages()[-1])") || SP=/usr/local/lib/python3.12/site-packages
echo "isolated-test site-packages: $SP"

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
bad=0

if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" = "$PARENT_SHA" ]; then
  echo "ok: HEAD is the pinned parent commit"
else
  echo "FAIL: HEAD is not the pinned parent commit $PARENT_SHA" >&2; bad=1
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  bad=1
else
  echo "ok: fix commit not present in the working clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  echo "FAIL: the working clone has '$ncommits' reachable commits; it must contain exactly the pinned parent commit (history was fetched or added)" >&2
  bad=1
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

saw_fix=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M $SRCMOD")
      saw_fix=1 ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad=1 ;;
    " M "*) echo "FAIL: a tracked file outside the library source was modified: $line" >&2; bad=1 ;;
    "?? "*) echo "FAIL: unexpected untracked file inside the repository: $line" >&2; bad=1 ;;
    "M  "*|"MM "*|"A  "*|"D  "*|"R  "*|"RM "*|" C "*|" M"*)
      echo "FAIL: staged or unusual working-tree entry: $line" >&2; bad=1 ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$saw_fix" = 1 ]; then
  echo "ok: the library source module carrying the summary path is modified (a fix was implemented)"
else
  echo "FAIL: no library source module is modified (no fix implemented)" >&2
  bad=1
fi
[ "$bad" = 1 ] && reward=0

# ---------- 1. rebuild and reinstall from the repaired tree -------------------
echo "== rebuild + reinstall from the repaired tree =="
if ( cd "$SRC" && pip install --no-build-isolation --no-deps --no-cache-dir \
     --disable-pip-version-check --config-settings=builddir=/opt/sm-build . ) \
     > /tmp/reinstall.log 2>&1; then
  echo "ok: pip install from the repaired tree succeeded"
else
  echo "FAIL: pip install from the repaired tree failed" >&2
  tail -30 /tmp/reinstall.log | sed 's/^/    /' >&2
  reward=0
fi

# The installed library must reflect the repaired tree, not the buggy parent.
if ! PYTHONPATH="$SP" python3 -S - <<'EOF'
import pathlib
import statsmodels.regression.mixed_linear_model as m
inst = pathlib.Path(m.__file__)
src = pathlib.Path("/app/src/statsmodels/regression/mixed_linear_model.py")
if not inst.exists() or inst.read_bytes() != src.read_bytes():
    raise SystemExit("installed module differs from the repaired tree")
print("installed at", inst)
EOF
then
  echo 'FAIL: the installed statsmodels/regression/mixed_linear_model.py is not byte-identical to the repaired tree (the reinstall did not pick up the fix)' >&2
  reward=0
else
  echo "ok: installed module is byte-identical to the repaired tree"
fi

# ---------- 2. golden test + the project's own test module --------------------
# The project's own test module for this feature, extracted byte-for-byte
# from the fix release into /opt/golden (test_lme.py stands alone there with
# the project's 'results' package beside it). Running it against the
# installed library exercises the 30+ existing mixed-model tests AND the
# upstream regression test test_summary_title; the module must be fully
# green, and the regression test must be among the passed tests.
echo "== golden test + the project's own test module (/opt/golden/test_lme.py) =="
if [ ! -f "$GOLDEN/test_lme.py" ] || ! grep -q "def test_summary_title" "$GOLDEN/test_lme.py"; then
  echo "FAIL: golden regression-test module missing from image" >&2
  reward=0
else
  if ( cd /tmp && PYTHONPATH="$SP" python3 -S -m pytest -v -p no:cacheprovider "$GOLDEN/test_lme.py" ) \
       > /tmp/module.out 2>&1; then
    if grep -q "test_lme.py::TestMixedLMSummary::test_summary_title PASSED" /tmp/module.out; then
      echo "ok: project test_lme.py module passed, including the upstream regression test_summary_title"
    else
      echo "FAIL: test_lme.py passed but the regression test test_summary_title did not run" >&2
      tail -40 /tmp/module.out | sed 's/^/    /' >&2
      reward=0
    fi
  else
    echo "FAIL: the project's own test_lme.py module did not pass against the repaired tree" >&2
    tail -80 /tmp/module.out | sed 's/^/    /' >&2
    reward=0
  fi
fi

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
hidden_fail=0
rm -rf /tmp/verify && mkdir -p /tmp/verify
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  if ! cp "$case"/*_test.py /tmp/verify/ 2>/dev/null; then
    echo "FAIL: could not stage hidden case $name into the scratch dir" >&2
    reward=0; hidden_fail=1
    continue
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2
  reward=0; hidden_fail=1
fi
if [ "$hidden_fail" = 0 ]; then
  if ( cd /tmp/verify && PYTHONPATH="$SP" python3 -S -m pytest -v -p no:cacheprovider zz_hidden_*_test.py ) \
       > /tmp/hidden.out 2>&1; then
    npass=$(grep -c "PASSED" /tmp/hidden.out || true)
    echo "ok: all hidden cases passed ($npass tests across $n_hidden case dirs)"
  else
    echo "FAIL: one or more hidden cases failed" >&2
    tail -80 /tmp/hidden.out | sed 's/^/    /' >&2
    reward=0
  fi
fi

# ---------- 4. raw reproduction snippet ---------------------------------------
echo "== raw reproduction =="
if ( cd /tmp && PYTHONPATH="$SP" python3 -S - <<'EOF'
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

title = "Custom MixedLM Summary"
assert res.summary(title=title).title == title, "summary ignored the requested title"
assert res.summary().title == "Mixed Linear Model Regression Results"
assert res.summary(title=None).title == "Mixed Linear Model Regression Results"
print("ok: summary honors the requested title and keeps the default only when none is given")
EOF
) > /tmp/repro.out 2>&1; then
  echo "ok: reproduction snippet shows the title argument is honored"
else
  echo "FAIL: reproduction snippet still shows the title argument ignored (or errors)" >&2
  tail -40 /tmp/repro.out | sed 's/^/    /' >&2
  reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0