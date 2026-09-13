#!/bin/bash
# Verifier for ballast-rudder: an upstream-clone debugging task on python/mypy.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# when the rvalue of a multiple assignment (`a, b = f(...)`) is a call to an
# overloaded function and the assignment-target context re-selects the callee
# overload, the re-inferred return type is not always a fixed-length tuple,
# and the checked-out checker aborts the whole type-check run with INTERNAL
# ERROR at the assignment instead of diagnosing it. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, no history
#      was fetched or committed, no tracked file was deleted, the only
#      modified tracked files are source files under mypy/ with at least one
#      such modification present, test data and the test harness are
#      untouched, and `python3 -m mypy` from /app/src resolves to the
#      checked-out tree);
#   1. runs the user-visible reproduction: mypy must exit 1 on /app/repro.py
#      and print the real 'Incompatible types in assignment' diagnostic with
#      no INTERNAL ERROR;
#   2. copies in and runs the project's own regression test for this bug,
#      extracted at image build time from the fix commit into /opt/golden/;
#   3. runs a meaningful slice of the project's own existing checker suite
#      from the tree (every check-*.test case in the tuple, overloading,
#      inference, namedtuple and typevar-tuple data files), proving the fix
#      broke nothing else;
#   4. runs three authored hidden cases exercising the same reinference code
#      path from inputs the upstream regression test does not use (an
#      overloaded method call, a non-tuple 'list[Any]' overload return, and a
#      starred unpacking target), each of which crashes the unfixed checker
#      and passes the fixed one.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
# The verifier runs in the same container as the trial (shared mode); write the
# losing value up front so a trial that kills the verifier mid-run or pre-seeds
# the reward file cannot leave a win behind. The end of this script always
# overwrites the file with the honestly computed reward.
echo 0 > /logs/verifier/reward.txt
reward=1

SRC=/app/src
PARENT_SHA=5bb72b788d5c031244f04f30f571f6fa199871ad
FIX_SHA=0221c8018430c27607ff5e41d3127bd48a3e6170
GOLDEN=/opt/golden/check-tuples.test
# The reproduction input and the golden test data are harness-owned inputs that
# the trial must not doctor: /app/repro.py is the shipped reproduction file,
# and /opt/golden/check-tuples.test is the fix-commit regression bytes
# extracted at image build time. A trial that rewrites either one is escaping
# the task, not solving it, so the verifier re-checks their hashes. (At image
# build time the Dockerfile extracts /opt/golden/check-tuples.test with this
# exact hash, and /app/repro.py is the byte-for-byte content of
# environment/files/repro.py.)
REPRO_SHA=44de802b6f2b9b6bd679a7d77303c3f7e279f782311683533efe5634131f9ae4
GOLDEN_SHA=f3159fac0a3ba4b2915c2b63df0b7fd5772c343d78e2a113fba4a8b84c5a6adc
GOLDEN_NAMES="testMultipleAssignmentWithOverloadReinferredAsHomogeneousTuple or testMultipleAssignmentWithOverloadReinferredAsNonTuple"
SLICE_NAMES="check-tuples or check-overloading or check-inference or check-typevar-tuple or check-namedtuple or check-inference-context"
HIDDEN_NAMES="testMultiAssignmentOverloadReinferredMethodReceiver or testMultiAssignmentOverloadReinferredToListOverload or testMultiAssignmentOverloadReinferredStarMarker"

export PYTHONDONTWRITEBYTECODE=1

run_pytest () {  # run_pytest LABEL OUT EXPECT ...args  (cwd = SRC)
  # EXPECT is an egrep pattern that must be found in the pytest summary when
  # the run exits 0; it proves the tests we mean actually executed and passed
  # (a run that skipped or deselected everything exits 0 too, so exit status
  # alone is not enough). Pass "" when no assertion is needed.
  label="$1"; out="$2"; expect="$3"; shift 3
  if ( cd "$SRC" && python3 -m pytest "$@" -o addopts="" -q -p no:cacheprovider > "$out" 2>&1 ); then
    if [ -n "$expect" ] && ! grep -qE "$expect" "$out"; then
      echo "FAIL: $label: run reported success but the summary is missing '$expect' (the tests did not actually run as required)" >&2
      tail -40 "$out" | sed 's/^/    /' >&2
      reward=0
      return 1
    fi
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
  echo "FAIL: /app/src is not a git clone" >&2; reward=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
else
  echo "ok: fix commit not present in the working clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  echo "FAIL: the working clone contains $ncommits commits; it must contain exactly the pinned parent commit (history was fetched or added)" >&2
  reward=0
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

saw_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M mypy/"*)
      case "$line" in
        " M mypy/test/"*|" M mypy/test-data/"*)
          echo "FAIL: the test harness under mypy/test/ was modified: $line" >&2; bad_tree=1 ;;
        *)
          saw_mod=1 ;;
      esac
      ;;
    " M "*) # modified tracked file outside mypy/
      echo "FAIL: a tracked file outside mypy/ was modified (e.g. test data or config): $line" >&2
      bad_tree=1
      ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? "*) # untracked files: allowed only where the task expects them (the
      # agent's own test-data additions, which the verifier overwrites anyway)
      # and for tool caches. Anything else -- notably arbitrary new files at
      # the repo root, where a file could shadow pytest/pyproject config or
      # hook into a later run -- is treated as escape artistry, not a fix.
      case "$line" in
        "?? mypy/"*)
          echo "FAIL: a new file was added inside the mypy package: $line" >&2; bad_tree=1 ;;
        "?? test-data/"*|"?? .pytest_cache/"*|"?? .mypy_cache/"*|"?? __pycache__/"*)
          : ;;
        "?? .pytest_cache"|"?? .mypy_cache"|"?? __pycache__")
          : ;;
        *)
          echo "FAIL: unexpected untracked file/dir in the repo root or outside the allowed areas: $line" >&2; bad_tree=1 ;;
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2; reward=0
else
  echo "ok: at least one source file under mypy/ is modified"
fi

if [ "$(cd "$SRC" && python3 -c "import mypy.checker, os; print(os.path.realpath(mypy.checker.__file__))" 2>/dev/null)" != "$SRC/mypy/checker.py" ]; then
  echo "FAIL: 'import mypy' from /app/src does not resolve to the checked-out tree" >&2
  reward=0
else
  echo "ok: mypy resolves to $SRC/mypy/checker.py"
fi

# ---------- 1. reproduction: real diagnostic, no INTERNAL ERROR ---------------
echo "== reproduction (/app/repro.py) =="
if [ "$(sha256sum /app/repro.py 2>/dev/null | cut -d' ' -f1)" != "$REPRO_SHA" ]; then
  echo "FAIL: /app/repro.py is no longer the shipped reproduction input (hash $REPRO_SHA); the input may not be doctored" >&2
  reward=0
else
  echo "ok: /app/repro.py is the shipped reproduction input"
fi
set +e
( cd "$SRC" && python3 -m mypy --no-incremental --cache-dir=/tmp/mycache /app/repro.py ) > /tmp/repro.out 2>&1
repro_rc=$?
set -e
if [ "$repro_rc" != "1" ]; then
  echo "FAIL: mypy on /app/repro.py exited $repro_rc, expected 1 (diagnostics found, no crash)" >&2
  tail -20 /tmp/repro.out | sed 's/^/    /' >&2
  reward=0
elif grep -q "INTERNAL ERROR" /tmp/repro.out; then
  echo "FAIL: /app/repro.py still aborts with INTERNAL ERROR" >&2
  tail -20 /tmp/repro.out | sed 's/^/    /' >&2
  reward=0
elif ! grep -q 'Incompatible types in assignment (expression has type "int", variable has type "str")' /tmp/repro.out; then
  echo "FAIL: the real assignment diagnostic is missing from the output" >&2
  tail -20 /tmp/repro.out | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: /app/repro.py is diagnosed (exit 1, correct message, no INTERNAL ERROR)"
fi

# ---------- 2. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif [ "$(sha256sum "$GOLDEN" | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
  echo "FAIL: /opt/golden/check-tuples.test is no longer the fix-commit regression bytes (hash $GOLDEN_SHA); the golden test data may not be doctored" >&2
  reward=0
else
  echo "ok: golden test is the fix-commit bytes"
  cp "$GOLDEN" "$SRC/test-data/unit/check-tuples.test"
  run_pytest "golden testMultipleAssignmentWithOverloadReinferred*" /tmp/golden.out '2 passed' \
    mypy/test/testcheck.py -k "$GOLDEN_NAMES" || true
fi

# ---------- 3. the project's own existing checker suite slice ----------------
echo "== the project's own existing checker suite (tuple/overload/inference slice) =="
run_pytest "existing checker suite slice" /tmp/slice.out 'passed.*deselected' \
  mypy/test/testcheck.py -k "$SLICE_NAMES" || true

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  cp "$case"*.test "$SRC/test-data/unit/check-hidden-$n_hidden.test"
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi
run_pytest "hidden generalization cases" /tmp/hidden.out '3 passed' \
  mypy/test/testcheck.py -k "$HIDDEN_NAMES" || true

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0