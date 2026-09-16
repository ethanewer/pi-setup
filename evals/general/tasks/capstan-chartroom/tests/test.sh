#!/bin/bash
# Verifier for capstan-chartroom: an upstream-clone debugging task on
# statsmodels/statsmodels.
#
# Bug (upstream issue #9891): describe()/Description on a zero-row DataFrame
# raises instead of returning a summary. Numeric columns die with
# "ValueError: Length of values (2) does not match length of index (1)" from
# the pandas empty-result path of df.apply(_mode); all-categorical input dies
# with "KeyError: 2" when the code indexes an empty Jarque-Bera apply result.
# The agent must fix the real checkout at /app/src. The verifier:
#   0. asserts tree provenance: HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, exactly
#      one commit reachable, no deletions/additions/staging, the test module
#      is byte-identical to the golden copy extracted at image build time,
#      and the only modified tracked source file is the library module the
#      fix requires (it must carry a modification);
#   1. rebuilds and reinstalls statsmodels from the repaired tree into the
#      warmed meson build dir (incremental, seconds) and asserts the
#      installed module is byte-identical to the repaired tree's module;
#   2. runs the project's own test_descriptivestats.py module from a scratch
#      dir against the installed library -- the 15 existing tests plus the
#      upstream parametrized test_empty_rows regression (3 cases) must all
#      pass;
#   3. runs three authored hidden cases that exercise the same empty-input
#      path from inputs the upstream test does not use (multi-column numeric
#      frames, a zero-row Series input, nullable Int64, custom stats
#      selections, categorical top/freq on an empty mixed frame, ci bounds);
#   4. runs the raw reproduction snippet: describe() on zero-row numeric and
#      categorical frames returns a summary with nobs == 0 and NaN stats.
#
# Every behavioural phase is run with `python3 -S` (no site processing):
# a runtime "wrapper" planted through site-packages `*.pth`,
# `sitecustomize.py`, `usercustomize.py` or a user-site directory is never
# executed, so the repaired source tree itself -- and not any import-time
# monkeypatch -- is the only way the tests can pass. This was added because
# the unaided interpreter lets a `.pth` hook serve a fixed module at import
# time while /app/src stays broken (verified in review: 18/18 + 6/6 passing
# with the bug still in the tree).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=52f10d214d4dc02e9b521b9f9a83c5e3d4880f94
FIX_SHA=e30aa8337deebbb902d886b291ab206c3ce4e639
GOLDEN=/opt/golden
TESTMOD="statsmodels/stats/tests/test_descriptivestats.py"
SRCMOD="statsmodels/stats/descriptivestats.py"

# Where the pinned interpreter keeps its packages; every isolated invocation
# splices this onto sys.path, since python3 -S does not add it automatically.
SP=$(python3 -c "import site; print(site.getsitepackages()[0])")

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

# The test module must stay exactly as the image shipped it (fix release bytes).
if [ -f "$SRC/$TESTMOD" ] && cmp -s "$SRC/$TESTMOD" "$GOLDEN/test_descriptivestats.py"; then
  echo "ok: $TESTMOD is byte-identical to the golden copy"
else
  echo "FAIL: $TESTMOD is missing or differs from the golden copy; the test module must remain exactly as the fix intended it" >&2
  bad=1
fi

saw_fix=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M $SRCMOD")
      saw_fix=1 ;;
    " M $TESTMOD")
      : ;;  # image overlay; byte identity asserted above
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad=1 ;;
    " M "*) echo "FAIL: a tracked file outside the library source was modified: $line" >&2; bad=1 ;;
    "?? "*) echo "FAIL: unexpected untracked file inside the repository: $line" >&2; bad=1 ;;
    "M  "*|"MM "*|"A  "*|"D  "*|"R  "*|"RM "*|" C "*|" M"*)
      echo "FAIL: staged or unusual working-tree entry: $line" >&2; bad=1 ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$saw_fix" = 1 ]; then
  echo "ok: the library source module carries a modification (a fix was implemented)"
else
  echo "FAIL: the library source module is unmodified (no fix implemented)" >&2
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
if ! python3 -S -c "
import sys
sys.path[:0] = ['$SP']
import pathlib
import statsmodels.stats.descriptivestats as d
inst = pathlib.Path(d.__file__)
src = pathlib.Path('/app/src/statsmodels/stats/descriptivestats.py')
if not inst.exists() or inst.read_bytes() != src.read_bytes():
    raise SystemExit('installed module differs from the repaired tree')
print('installed at', inst)
"; then
  echo 'FAIL: the installed statsmodels/stats/descriptivestats.py is not byte-identical to the repaired tree (the reinstall did not pick up the fix)' >&2
  reward=0
else
  echo "ok: installed module is byte-identical to the repaired tree"
fi

# ---------- 2. golden test + the project's own module -------------------------
echo "== golden test + the project's own test module =="
rm -rf /tmp/verify && mkdir -p /tmp/verify
cp "$GOLDEN/test_descriptivestats.py" /tmp/verify/
if ( cd /tmp/verify && python3 -S -c "
import sys, glob
sys.path[:0] = ['$SP', '.']
import pytest
raise SystemExit(pytest.main(['test_descriptivestats.py', '-v']))
" ) > /tmp/module.out 2>&1; then
  np3=$(grep -c "test_empty_rows\[.*\] PASSED" /tmp/module.out || true)
  if [ "$np3" -lt 3 ]; then
    echo "FAIL: test_empty_rows ran fewer than 3 parametrizations (log shows $np3)" >&2
    tail -40 /tmp/module.out | sed 's/^/    /' >&2
    reward=0
  else
    echo "ok: project's own test_descriptivestats.py module passed ($np3/3 regression parametrizations)"
  fi
else
  echo "FAIL: the project's own test_descriptivestats.py module did not pass" >&2
  tail -60 /tmp/module.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
hidden_fail=0
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
  if ( cd /tmp/verify && python3 -S -c "
import sys, glob
sys.path[:0] = ['$SP', '.']
import pytest
raise SystemExit(pytest.main(sorted(glob.glob('zz_hidden_*_test.py')) + ['-v']))
" ) > /tmp/hidden.out 2>&1; then
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
if ( cd /tmp && python3 -S -c "
import sys
sys.path[:0] = ['$SP']
import pandas as pd
from statsmodels.stats.descriptivestats import describe

df = pd.DataFrame({'a': pd.Series([], dtype='float64')})
res = describe(df)
assert (res.loc['nobs'] == 0).all()
assert (res.loc['missing'] == 0).all()
assert res.loc['mean', 'a'] != res.loc['mean', 'a'], 'mean of empty column must be NaN'
assert res.loc['median', 'a'] != res.loc['median', 'a'], 'median of empty column must be NaN'
assert list(res.columns) == ['a']

dfc = pd.DataFrame({'a': pd.Series([], dtype='category')})
resc = describe(dfc)
assert (resc.loc['nobs'] == 0).all()
assert (resc.loc['missing'] == 0).all()
print('ok: summary returned with nobs == 0 and NaN statistics')
" ) > /tmp/repro.out 2>&1; then
  echo "ok: reproduction snippet returns a summary instead of raising"
else
  echo "FAIL: reproduction snippet still raises or returns the wrong summary" >&2
  tail -40 /tmp/repro.out | sed 's/^/    /' >&2
  reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0