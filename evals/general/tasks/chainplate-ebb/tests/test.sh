#!/usr/bin/env bash
# Verifier for chainplate-ebb: an upstream-clone debugging task on
# scipy/scipy.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# scipy.optimize.minimize silently rewrites a caller's dimension-agnostic
# Bounds object in place (scalar lb/ub are replaced by broadcast arrays sized
# to the current problem). The verifier:
#   0. asserts tree provenance: HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, exactly one commit exists, every
#      tracked file except scipy/optimize/_minimize.py is byte-identical to
#      the pinned commit (submodule gitlinks skipped), no untracked
#      non-ignored files, and `import scipy` resolves to the checked-out tree;
#   1. runs a subset of the project's own existing optimize tests against the
#      agent's tree to prove the fix broke nothing else;
#   2. copies in the project's own regression tests for this bug, extracted at
#      image build time from the fix commit into /opt/golden/, and requires
#      test_minimize_does_not_mutate_bounds (8 methods) and
#      test_minimize_bounds_reusable_across_sizes to pass (they fail against
#      the parent tree: the image build asserts the bug is present), then
#      restores the tree's own test_optimize.py;
#   3. runs the exact issue reproduction command from the instruction;
#   4. runs three authored hidden cases that reach the same code path from
#      inputs the upstream test never uses (reuse across sizes with l-bfgs-b,
#      five methods with keep_feasible and scalar-state shape checks, a mixed
#      three-call sequence across methods and sizes);
#   5. checks the /app/explanation.md deliverable.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=68942fb357ee133e75709e91959d322325fffb90
FIX_SHA=b92b297a5a0c372600bffffd4dc83513be9bfd39
GOLDEN=/opt/golden/test_optimize.py
GOLDEN_SHA=4fdfa623c32c88c8f2b351ab33ad742ef63caa2a9e2b74b8d285139b2a4c688f

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

# ---------- pre-check: the fix must live INSIDE the checked-out tree --------
# The behavioral checks below run plain `python3`/pytest in this container. An
# interpreter-level shim (a sitecustomize/usercustomize script, a replaced
# python wrapper, or a .pth import) could wrap `scipy.optimize.minimize` at
# startup and satisfy them while the tree's own (buggy) module stays
# untouched. Reject any minimize whose code does not come from the tree's own
# _minimize.py: the fix must be a real edit to the checked-out source.
if ! python3 -c "
import scipy.optimize as so
f = so.minimize
code = getattr(f, '__code__', None)
if code is None or not getattr(code, 'co_filename', '').startswith('$SRC/'):
    raise SystemExit('minimize is not defined inside the checked-out tree')
if getattr(f, '__module__', None) != 'scipy.optimize._minimize':
    raise SystemExit('minimize is not scipy.optimize._minimize.minimize')
" >/dev/null 2>&1; then
  fail "scipy.optimize.minimize is not the tree's own implementation (an interpreter-startup shim is not the fix)"
else
  echo "ok: minimize is the tree's own implementation under $SRC"
fi

# Purge bytecode caches: a planted __pycache__ build of the module would let
# the buggy source bytes stay byte-identical to the parent commit while the
# interpreter executes different (patched) code. The tree is re-verified by
# source below, so removing caches cannot hurt a real fix.
find "$SRC" -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true

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

# Content-level scope check: every tracked file except the single source file
# the bug is in (scipy/optimize/_minimize.py, which the agent must locate
# itself) must be byte-identical to the pinned commit's blob. Comparison is
# raw bytes (`git cat-file blob | cmp`): `git hash-object` would apply the
# CRLF->LF clean filter for files that .gitattributes marks `text`, which
# falsely reports upstream files that contain CRLF bytes as modified. Tracked
# submodules are gitlinks (mode 160000): they have no blob and are validated
# by the fact that HEAD is still the parent commit.
bad_tree=0
saw_fix=1
gitlinks=$(git -C "$SRC" ls-files -s | awk '$1=="160000"{print $4}' | sed 's/^/ /; s/$/ /')
gitlinks=" $gitlinks "
while IFS= read -r -d '' f; do
  if [ "$f" = "scipy/optimize/_minimize.py" ]; then
    saw_fix=0
    continue
  fi
  case " $gitlinks " in
    *" $f "*) continue ;;  # submodule gitlink; pointer fixed by HEAD == parent
  esac
  if ! git -C "$SRC" cat-file -e "$PARENT_SHA:$f" 2>/dev/null; then
    echo "FAIL: tracked file not in parent tree: $f (a new tracked file?)" >&2
    bad_tree=1
    continue
  fi
  if ! git -C "$SRC" cat-file blob "$PARENT_SHA:$f" 2>/dev/null | cmp -s - "$SRC/$f"; then
    if [ -L "$SRC/$f" ]; then
      tgt=$(readlink "$SRC/$f" 2>/dev/null || true)
      if ! git -C "$SRC" cat-file blob "$PARENT_SHA:$f" 2>/dev/null | cmp -s - <(printf '%s' "$tgt"); then
        echo "FAIL: tracked file differs from the pinned commit: $f" >&2
        bad_tree=1
      fi
    else
      echo "FAIL: tracked file differs from the pinned commit: $f" >&2
      bad_tree=1
    fi
  fi
done < <(git -C "$SRC" ls-files -z)
if [ "$saw_fix" != 0 ]; then
  fail "scipy/optimize/_minimize.py is not a tracked file (garbled tree)"
fi
while IFS= read -r -d '' f; do
  echo "FAIL: untracked non-ignored file: $f" >&2
  bad_tree=1
done < <(git -C "$SRC" ls-files --others -z --exclude-standard)
if [ "$bad_tree" = 1 ]; then
  fail "working tree modified outside scipy/optimize/_minimize.py"
else
  echo "ok: every tracked file except scipy/optimize/_minimize.py is byte-identical to the pinned commit; no stray files"
fi

if ! python3 -c "
import scipy
assert scipy.__file__.startswith('$SRC'), scipy.__file__
import scipy.optimize
" >/dev/null 2>&1; then
  fail "'import scipy' does not resolve to the checked-out tree at /app/src"
else
  echo "ok: import scipy resolves to $SRC/scipy"
fi

# explanation.md deliverable
if [ ! -s /app/explanation.md ]; then
  fail "the deliverable /app/explanation.md is missing or empty"
else
  if ! grep -qi "mutat" /app/explanation.md; then
    fail "/app/explanation.md does not discuss the mutation of the caller's bounds object"
  else
    echo "ok: /app/explanation.md exists and discusses the root cause"
  fi
fi

# ---------- 1. the project's own existing optimize tests ---------------------
echo "== the project's own existing suite (targeted optimize tests) =="
run_pytest "existing tests: bounds/limits subset" /tmp/own.out \
  "scipy/optimize/tests/test_optimize.py::test_bounds_with_list" \
  "scipy/optimize/tests/test_optimize.py::test_all_bounds_equal" \
  "scipy/optimize/tests/test_optimize.py::test_all_bounds_equal_writable" \
  "scipy/optimize/tests/test_optimize.py::test_minimize_maxiter_noninteger" || true

# ---------- 2. golden: the upstream regression tests for this bug ------------
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
    echo "ok: /opt/golden/test_optimize.py is the fix-commit regression file (sha $GOLDEN_SHA)"
    cp "$GOLDEN" "$SRC/scipy/optimize/tests/test_optimize.py"
    run_pytest "golden test_minimize_does_not_mutate_bounds (8 methods)" /tmp/golden1.out \
      "scipy/optimize/tests/test_optimize.py::test_minimize_does_not_mutate_bounds" || true
    run_pytest "golden test_minimize_bounds_reusable_across_sizes" /tmp/golden2.out \
      "scipy/optimize/tests/test_optimize.py::test_minimize_bounds_reusable_across_sizes" || true
    # restore the tree's own test file so the checkout stays pristine
    git -C "$SRC" checkout -- scipy/optimize/tests/test_optimize.py 2>/dev/null || true
  fi
fi

# ---------- 3. the exact issue reproduction command ---------------------------
echo "== issue reproduction =="
if ( cd "$SRC" && python3 - <<'EOF' > /tmp/repro.out 2>&1
import numpy as np
from scipy import optimize
bounds = optimize.Bounds(0., np.inf)
lb, ub = bounds.lb, bounds.ub
optimize.minimize(optimize.rosen, [0.5, 0.5], method='trust-constr', bounds=bounds)
assert bounds.lb is lb and bounds.ub is ub, 'mutated'
print("lb is lb:", bounds.lb is lb, " ub is ub:", bounds.ub is ub)
EOF
); then
  echo "ok: the issue reproduction passes"
  sed 's/^/    /' /tmp/repro.out
else
  fail "the issue reproduction still asserts (caller's Bounds was mutated)"
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