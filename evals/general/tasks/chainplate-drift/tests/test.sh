#!/bin/bash
# Verifier for chainplate-drift: an upstream-clone debugging task on
# scikit-image.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# EllipseModel.estimate() has no minimum-points check, so with 4 arbitrary
# points it returns True with fabricated parameters, and with <= 3 points it
# fails silently. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, exactly one commit exists, the
#      only modified tracked file is skimage/measure/fit.py, no tracked test
#      file was doctored, and `import skimage` resolves to the checked-out
#      tree);
#   1. runs the project's own regression test for this bug, extracted at
#      image build time from the fix commit into /opt/golden/test_fit.py,
#      and requires it to pass against the agent's repaired tree (it fails
#      against the parent tree: the image build asserts that with
#      'DID NOT WARN');
#   2. runs the whole golden test_fit.py (30 tests: line/circle/ellipse/
#      ransac estimators) as the 'fix broke nothing else' proof. Note that
#      this must be the golden (fix-era) file, not the checked-out one: the
#      checked-out test_fit.py::test_ellipse_model_estimate_failers asserts
#      the OLD behaviour (3-collinear points must return False with no
#      expectation of the new warning), so under the project's pytest
#      filterwarnings=error config a correct fix makes exactly that one
#      outdated test fail — upstream updated that same test in the same
#      commit as the fix;
#   3. runs the exact issue reproductions from the instruction;
#   4. runs three authored hidden cases the upstream test does not use:
#      four non-degenerate points (fabricated-fit vector, asserts False +
#      exact warning + params stay unset), three collinear points plus 2- and
#      1-point inputs (silent-failure vector, asserts the exact warning is
#      the only diagnostic), and a genuine 5-point ellipse that must still
#      fit with the true parameters (guard against over-fixing).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=fff7deabe28fb6039c26588f751e9cad88354f19
FIX_SHA=96834cf3d57c4a9bad82a471a5548be3ad53a4fa
GOLDEN=/opt/golden/test_fit.py
GOLDEN_SHA=5a8c9222b5ff03a5d4d28a4a80b7b77795ba9a6b2b403f1e342f70c3bcae904a

export PYTHONDONTWRITEBYTECODE=1

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

run_pytest () {  # run_pytest LABEL OUT ...args  (cwd = SRC)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -o addopts= -p no:cacheprovider -q > "$out" 2>&1 ); then
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
    " M skimage/measure/fit.py")
      saw_mod=1
      ;;
    " M "*) # modified tracked file outside the fix target
      echo "FAIL: a tracked file other than skimage/measure/fit.py was modified: $line" >&2
      bad_tree=1
      ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? "*) # untracked files allowed only outside the package and the tests
      case "$line" in
        "?? skimage/"*|"?? tests/"*)
          echo "FAIL: a new file was added inside skimage/ or tests/: $line" >&2
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
  echo "ok: skimage/measure/fit.py differs from the pinned commit"
fi

if ! ( cd / && python3 -c "import skimage; import sys; sys.exit(0 if skimage.__file__ and skimage.__file__.startswith('$SRC/skimage') else 3)" >/dev/null 2>&1 ); then
  fail "'import skimage' does not resolve to the checked-out tree at /app/src"
else
  echo "ok: import skimage resolves to $SRC/skimage"
fi

# The fix must live in the deliverable's own code, not in a wrapper injected
# into the interpreter. A trial runs as root, so an agent can write e.g.
# site-packages/sitecustomize.py or a .pth that monkeypatches
# EllipseModel.estimate to behave correctly while /app/src keeps the bug;
# such a wrapper survives the golden test's pytest.warns assertions (the
# stacklevel check included) if it reproduces the guard faithfully. Kill the
# whole class: require that the exact function the tests exercise is the one
# defined in the deliverable file (its source FILE must be fit.py) and that
# the guard text is present in that file's own bytes.
if ! ( cd / && python3 -P - <<'PYSRCCHK'
import inspect
from skimage.measure import EllipseModel
fn = EllipseModel.estimate
srcfile = inspect.getsourcefile(fn)
if not srcfile or srcfile != "/app/src/skimage/measure/fit.py":
    raise SystemExit(f"EllipseModel.estimate is not defined in the deliverable file (got {srcfile!r})")
if "Need at least 5 data points to estimate an ellipse." not in inspect.getsource(fn):
    raise SystemExit("the guard is not part of the definition of EllipseModel.estimate")
PYSRCCHK
); then
  fail "EllipseModel.estimate is wrapped or injected outside /app/src/skimage/measure/fit.py, or its definition lacks the guard"
else
  echo "ok: EllipseModel.estimate is the function defined in $SRC/skimage/measure/fit.py, guard text inside its definition"
fi
if ! grep -q "Need at least 5 data points to estimate an ellipse" "$SRC/skimage/measure/fit.py" 2>/dev/null; then
  fail "the guard text is absent from /app/src/skimage/measure/fit.py itself"
else
  echo "ok: the guard text is present in $SRC/skimage/measure/fit.py"
fi

# ---------- 1. golden: the upstream regression test for this bug --------------
echo "== golden test (the project's own regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  fail "golden test missing from image"
  reward=0
else
  sha=$(sha256sum < "$GOLDEN" | cut -d' ' -f1)
  if [ "$sha" != "$GOLDEN_SHA" ]; then
    fail "golden test in image has unexpected hash $sha"
    reward=0
  else
    echo "ok: /opt/golden/test_fit.py is the fix-commit regression file (sha $GOLDEN_SHA)"
    run_pytest "golden test_ellipse_model_estimate_failers" /tmp/golden.out \
      "/opt/golden/test_fit.py::test_ellipse_model_estimate_failers" || true
  fi
fi

# ---------- 2. the project's own fitting/estimator test suite ---------------
# The whole golden (fix-era) test_fit.py: 30 tests covering every estimator
# in skimage/measure/fit.py. The checked-out test module is NOT used here:
# its test_ellipse_model_estimate_failers still asserts the pre-fix contract
# (silent False), which a correct fix intentionally violates (the new warning
# escapes it and is an error under the project's filterwarnings=error config;
# upstream updated that test in the same commit as the fix). The image build
# asserts the parent tree fails this golden file ('DID NOT WARN').
echo "== the project's own existing estimator tests (golden test_fit.py, 30 tests) =="
run_pytest "golden test_fit.py in full" /tmp/own.out "/opt/golden/test_fit.py" || true

# ---------- 3. the exact issue reproductions from the instruction ------------
echo "== issue reproductions =="
if [ "$reward" = 1 ] && ( cd "$SRC" && python3 -c "
import numpy as np
from skimage.measure import EllipseModel

m = EllipseModel()
ok = m.estimate(np.array([[0., 0.], [1., 2.], [3., 1.], [4., 5.]]))
print('4-point estimate ->', ok, ' params ->', m.params)
assert ok is False, '4-point fit still claims success'
assert m.params is None
" > /tmp/repro.out 2>&1 ); then
  echo "ok: 4 arbitrary points refuse with params unset"
  sed 's/^/    /' /tmp/repro.out
else
  fail "the 4-point reproduction still asserts (estimate returns True with fabricated params)"
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