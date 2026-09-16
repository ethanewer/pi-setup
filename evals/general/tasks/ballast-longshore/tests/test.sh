#!/usr/bin/env bash
# Verifier for ballast-longshore: an upstream-clone debugging task on
# matplotlib/matplotlib.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# ScalarFormatter.set_useOffset dispatches on `val in [True, False]` (value
# equality), so the numeric offset 1 is mistaken for the boolean True: the
# offset is reset to 0 and automatic offset mode is turned on. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, exactly one commit exists, the
#      only modified tracked file is lib/matplotlib/ticker.py, no new files
#      appeared under lib/matplotlib/ apart from __pycache__, `import
#      matplotlib` resolves to the checked-out tree, ScalarFormatter.
#      set_useOffset is *defined inside* $SRC/lib/matplotlib/ticker.py and the
#      value-equality dispatch is gone from the file, so the fixed behavior
#      must come from the tree and not from a wrapper installed elsewhere
#      (sitecustomize/.pth) -- the review layer proved such a wrapper scored 1
#      against the unguarded version);
#   1. copies in the project's own regression tests for this bug, extracted
#      at image build time from the fix commit into /opt/golden/, and
#      requires test_set_use_offset_int + test_set_use_offset_bool to both be
#      present in the collection AND to pass individually against the agent's
#      repaired tree (they fail against the parent tree: the image build
#      asserts the bug is present);
#   2. runs the project's own existing TestScalarFormatter tests (fixed
#      subset: must collect exactly 43 and report '43 passed', nothing
#      skipped) to prove the fix broke nothing else;
#   3. runs the exact issue reproduction command from the instruction;
#   4. runs three authored hidden cases: numpy numeric scalars equal to 0/1
#      (case-1-numpy-scalars), a stateful bool-vs-number toggling sequence on
#      one formatter incl. 0, 1.0 and 3.5 (case-2-zero-bool-toggling), and
#      functional tick-label formatting relative to a forced offset of 1
#      through set_locs (case-3-offset-formatting).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=91d115ec161286b70da1447f53844b909247741f
FIX_SHA=05a66bb2a46a67d0bb716239ecafa681b2832ea3
GOLDEN=/opt/golden/test_ticker.py
GOLDEN_SHA=4f4f143f40d4400e777ca2b1292cc171589103f5a33f5c2bd9f483c30a610d65

export PYTHONDONTWRITEBYTECODE=1

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

run_pytest () {  # run_pytest LABEL OUT ...args  (cwd = SRC)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  fail "the working clone contains $ncommits commits; it must contain exactly the pinned parent commit"
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

saw_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M lib/matplotlib/ticker.py")
      saw_mod=1
      ;;
    " M "*) # modified tracked file outside the fix target
      echo "FAIL: a tracked file other than lib/matplotlib/ticker.py was modified: $line" >&2
      bad_tree=1
      ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? "*) # untracked files allowed, except new files under lib/matplotlib/
      case "$line" in
        "?? lib/matplotlib/"*"__pycache__/"*) : ;;
        "?? lib/matplotlib/"*)
          echo "FAIL: a new file was added under lib/matplotlib/: $line" >&2
          bad_tree=1 ;;
        *) : ;;
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: lib/matplotlib/ticker.py differs from the pinned commit"
fi

if ! python3 -c "
import re
import matplotlib
from matplotlib.ticker import ScalarFormatter
assert matplotlib.__file__.startswith('$SRC'), matplotlib.__file__
m = ScalarFormatter.set_useOffset
f = m.__code__.co_filename
assert f == '$SRC/lib/matplotlib/ticker.py', ('set_useOffset is defined in', f)
src = open('$SRC/lib/matplotlib/ticker.py', encoding='utf-8').read()
# The bug is the code statement 'if val in [True, False]:'; comments that
# merely quote it must not be misread as the dispatch still being live.
assert not re.search(r'^\s*if\s+val\s+in\s+\[True,\s*False\]\s*:', src, re.M), \
       'value-equality dispatch still present in ticker.py'
" >/tmp/prov.out 2>&1; then
  fail "the fixed behavior must come from the tree: set_useOffset must be defined in $SRC/lib/matplotlib/ticker.py and the value-equality dispatch ('val in [True, False]') must be gone from it"
  tail -5 /tmp/prov.out | sed 's/^/    /' >&2
else
  echo "ok: set_useOffset is defined in $SRC/lib/matplotlib/ticker.py and the value-equality dispatch is gone"
fi

# explanation.md deliverable
if [ ! -s /app/explanation.md ]; then
  fail "the deliverable /app/explanation.md is missing or empty"
else
  if ! grep -qiE "offset" /app/explanation.md || ! grep -qiE "bool" /app/explanation.md; then
    fail "/app/explanation.md does not actually discuss the offset/boolean semantics"
  else
    echo "ok: /app/explanation.md exists and discusses the root cause"
  fi
fi

# ---------- 1. golden: the upstream regression tests for this bug -------------
echo "== golden test (the project's own regression tests for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  fail "golden test missing from image"
  reward=0
else
  sha=$(sha256sum < "$GOLDEN" | cut -d' ' -f1)
  if [ "$sha" != "$GOLDEN_SHA" ]; then
    fail "golden test in image has unexpected hash $sha"
    reward=0
  else
    echo "ok: /opt/golden/test_ticker.py is the fix-commit regression file (sha $GOLDEN_SHA)"
    cp "$GOLDEN" "$SRC/lib/matplotlib/tests/test_ticker.py"
    # Both upstream regression tests must be present in the collection (a
    # conftest hook could otherwise drop one of them from the run).
    if ( cd "$SRC" && python3 -m pytest --collect-only -q \
           "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_set_use_offset_int" \
           "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_set_use_offset_bool" \
           -p no:cacheprovider > /tmp/golden.collect 2>&1 ) \
       && grep -qE "test_set_use_offset_int" /tmp/golden.collect \
       && grep -qE "test_set_use_offset_bool" /tmp/golden.collect \
       && grep -qE "2 tests collected" /tmp/golden.collect; then
      echo "ok: both golden regression tests are present in the collection"
    else
      fail "golden regression tests are not both present in the collection"
      tail -10 /tmp/golden.collect | sed 's/^/    /' >&2
    fi
    # ... and each must actually run and pass (a conftest 'skip' would green
    # an empty or partial run otherwise).
    for gid in test_set_use_offset_int test_set_use_offset_bool; do
      if ( cd "$SRC" && python3 -m pytest \
           "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::$gid" \
           -p no:cacheprovider > "/tmp/golden-$gid.out" 2>&1 ) \
         && grep -qE "1 passed" "/tmp/golden-$gid.out" \
         && ! grep -qiE "skipped" "/tmp/golden-$gid.out"; then
        echo "ok: golden $gid passes"
      else
        fail "golden $gid did not pass"
        tail -15 "/tmp/golden-$gid.out" | sed 's/^/    /' >&2
      fi
    done
  fi
fi

# ---------- 2. the project's own existing ticker tests ------------------------
echo "== the project's own existing suite (TestScalarFormatter subset) =="
# This subset is fixed: the golden test file is hash-pinned and the deps are
# pinned, so it must collect exactly 43 tests. A conftest that drops or skips
# part of it changes that number.
if ( cd "$SRC" && python3 -m pytest --collect-only -q \
       "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_use_offset" \
       "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_set_use_offset_float" \
       "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_useMathText" \
       "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_offset_value" \
       "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_scilimits" \
       -p no:cacheprovider > /tmp/own.collect 2>&1 ) \
   && grep -qE "43 tests collected" /tmp/own.collect; then
  echo "ok: own-suite subset collects exactly 43 tests"
else
  fail "own-suite subset did not collect exactly 43 tests (expected 43)"
  tail -10 /tmp/own.collect | sed 's/^/    /' >&2
fi
run_pytest "existing TestScalarFormatter tests" /tmp/own.out \
  "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_use_offset" \
  "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_set_use_offset_float" \
  "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_useMathText" \
  "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_offset_value" \
  "lib/matplotlib/tests/test_ticker.py::TestScalarFormatter::test_scilimits" || true
if ! grep -qE "43 passed" /tmp/own.out || grep -qiE "skipped" /tmp/own.out; then
  fail "existing TestScalarFormatter subset did not run to completion (expected '43 passed', nothing skipped)"
  tail -20 /tmp/own.out | sed 's/^/    /' >&2
fi

# ---------- 3. the exact issue reproduction command ---------------------------
echo "== issue reproduction =="
if [ "$reward" = 1 ] && ( cd "$SRC" && python3 - <<'EOF' > /tmp/repro.out 2>&1
import matplotlib
matplotlib.use('Agg')
from matplotlib.ticker import ScalarFormatter
f = ScalarFormatter()
f.set_useOffset(1)
print('offset =', repr(f.offset), ' useOffset =', repr(f.get_useOffset()))
assert f.offset == 1 and f.get_useOffset() is False
EOF
); then
  echo "ok: the issue reproduction passes"
  sed 's/^/    /' /tmp/repro.out
else
  fail "the issue reproduction still asserts (offset=0 / useOffset=True)"
  tail -10 /tmp/repro.out 2>/dev/null | sed 's/^/    /' >&2 || true
fi

# ---------- 4. authored hidden cases -----------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  for f in "$case"test_*.py; do
    [ -f "$f" ] || continue
    n_hidden=$((n_hidden + 1))
    name=$(basename "$(dirname "$f")")/$(basename "$f")
    out="/tmp/hidden-${n_hidden}.out"
    if python3 "$f" > "$out" 2>&1; then
      echo "ok: hidden case $name"
      tail -2 "$out" | sed 's/^/    /'
    else
      fail "hidden case $name"
      tail -15 "$out" | sed 's/^/    /' >&2
    fi
  done
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0