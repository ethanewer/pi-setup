#!/bin/bash
# Verifier for cistern-beacon: an upstream-clone debugging task on sympy.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# linprog called with only the cost row and none of the constraint matrices
# dies with a misleading ValueError("must give A and B") deep inside the
# solver.  The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, exactly
#      the minimal source file is modified, and no new files appeared inside
#      the sympy package);
#   1. runs the project's own regression test for this bug (test_29368),
#      extracted at image build time from the fix commit into /opt/golden/;
#   2. runs the project's own existing simplex-module test file from the
#      tree, proving the fix broke nothing else;
#   3. runs at least two authored hidden cases (explicit empty constraint
#      matrices; other cost-row shapes, kinds and default-bounds forms) that
#      the upstream test does not use.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

# The verifier must measure the agent's tree, not anything the agent could
# inject into the interpreter.  Disable the per-user site directory so a
# usercustomize.py placed in a writable $HOME can never run in these python
# processes.  (System site-packages is root-owned in this image, but this
# keeps the gate robust regardless of how the trial user's HOME is set.)
export PYTHONNOUSERSITE=1

SRC=/app/src
PARENT_SHA=6a968f7201e5d9187b50dbdc2cc66b17594a59ac
FIX_SHA=66ee6e06934fede513c7504413baacbf80917186
GOLDEN=/opt/golden/test_simplex.py
PTCFG="$SRC/pyproject.toml"

# Expected sha256 of every test file the verifier relies on.  The golden
# regression test is extracted from the upstream fix commit at image build
# time (root-owned, /opt/golden) and the hidden cases are mounted from the
# harness.  If any of them is rewritten or replaced the verifier must score 0,
# not re-scoring a tampered test.  These are the bytes shipped in this task.
GOLDEN_SHA=10722f969fccd8c0c98df754e60fc54928ebbf24a1bd4cc1104da7f864ace706
HIDDEN_EXPLICIT_SHA=95290c6d1d402c6f1c6e2e5ee5e83c71401a3a974820aa8dbdfc8ce1e86171ac
HIDDEN_SHAPES_SHA=14a5497acefb85e297383b54ab9926d3ad306b580092e55ce9f6649cb467b5d0

check_sha () {  # check_sha FILE EXPECTED LABEL
  file="$1"; expected="$2"; label="$3"
  if [ ! -f "$file" ]; then
    echo "FAIL: $label file is missing" >&2; reward=0; return 1
  fi
  got=$(sha256sum "$file" | cut -d' ' -f1)
  if [ "$got" = "$expected" ]; then
    echo "ok: $label checksum matches"
    return 0
  fi
  echo "FAIL: $label file was modified (expected sha256 $expected, found $got)" >&2
  reward=0
  return 1
}

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -c "$PTCFG" -q -p no:cacheprovider > "$out" 2>&1 ); then
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
  echo "FAIL: /app/src is not a git checkout" >&2; reward=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M sympy/solvers/simplex.py$' | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only sympy/solvers/simplex.py may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? sympy/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the sympy package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- sympy/solvers/simplex.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if check_sha "$GOLDEN" "$GOLDEN_SHA" "golden test"; then
  run_pytest "golden test_29368" /tmp/golden.out "$GOLDEN::test_29368" \
    || true
fi

# ---------- 2. the project's own existing simplex-module suite ---------------
echo "== the project's own existing simplex tests =="
run_pytest "existing sympy/solvers/tests/test_simplex.py" /tmp/own.out sympy/solvers/tests/test_simplex.py \
  || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  # each hidden case directory carries exactly one test file; verify its
  # content is the shipped bytes before running it
  for tf in "$case"*.py; do
    [ -f "$tf" ] || continue
    case "$(basename "$tf")" in
      test_explicit_empty_constraints.py) exp_sha="$HIDDEN_EXPLICIT_SHA" ;;
      test_objective_shapes.py)          exp_sha="$HIDDEN_SHAPES_SHA" ;;
      *) echo "FAIL: unexpected extra file in hidden case $name: $(basename "$tf")" >&2; reward=0; continue ;;
    esac
    check_sha "$tf" "$exp_sha" "hidden case $name: $(basename "$tf")"
  done
  if ( cd "$SRC" && python3 -m pytest "$case" -c "$PTCFG" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0