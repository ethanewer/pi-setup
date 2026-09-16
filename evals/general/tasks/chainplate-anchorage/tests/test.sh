#!/usr/bin/env bash
# Verifier for chainplate-anchorage: an upstream-clone debugging task on
# matplotlib/matplotlib.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# Transform.contains_branch_seperately reports per-axis containment wrongly
# when the transform is a composite whose right-hand side is a blended
# (per-axis) transform (the composite has no override, so it falls back to
# the base implementation which answers BOTH axes with the whole-composite
# answer), and the base implementation returns a list where a pair of
# booleans is documented. The verifier:
#   0. asserts tree provenance: HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, exactly one commit exists, every
#      tracked file except lib/matplotlib/transforms.py is byte-identical to
#      the pinned commit (content hash, symlink-aware), no untracked
#      non-ignored files, and `import matplotlib` resolves to the checked-out
#      tree;
#   1. copies in the project's own regression test for this bug, extracted at
#      image build time from the fix commit into /opt/golden/, and requires
#      TestBasicTransform::test_contains_branch to pass against the agent's
#      repaired tree (it fails against the parent tree: the image build
#      asserts the bug is present);
#   2. runs a subset of the project's own existing TestBasicTransform tests
#      to prove the fix broke nothing else;
#   3. runs the exact issue reproduction command from the instruction;
#   4. runs three authored hidden cases that reach the same code path from
#      inputs the upstream test never uses (x-axis mirror, two-level nesting
#      + self-containment, return-type contract).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=74c7f9a598c4e32b3f551f75ed965f446d786ab1
FIX_SHA=00cbd9cd3255dcbcb75e3090b144a8e18a900247
GOLDEN=/opt/golden/test_transforms.py
GOLDEN_SHA=313b07123644596eb7067160a002208c4941750e36c790da560a641a82fc53f8

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

# Content-level scope check: every tracked file except the single source file
# the bug is in (lib/matplotlib/transforms.py, which the agent must locate
# itself) must be byte-identical to the pinned commit's blob. Symlinked
# tracked files (mpl-data image symlinks) are hashed by their link target.
bad_tree=0
saw_fix=1
while IFS= read -r -d '' f; do
  if [ "$f" = "lib/matplotlib/transforms.py" ]; then
    saw_fix=0
    continue
  fi
  want=$(git -C "$SRC" rev-parse "$PARENT_SHA:$f" 2>/dev/null || true)
  if [ -z "$want" ]; then
    echo "FAIL: tracked file not in parent tree: $f (a new tracked file?)" >&2
    bad_tree=1
    continue
  fi
  if [ -L "$SRC/$f" ]; then
    have=$(printf '%s' "$(readlink "$SRC/$f")" | git hash-object --stdin 2>/dev/null || true)
  else
    have=$(git -C "$SRC" hash-object -- "$SRC/$f" 2>/dev/null || true)
  fi
  if [ -z "$have" ] || [ "$have" != "$want" ]; then
    echo "FAIL: tracked file differs from the pinned commit: $f" >&2
    bad_tree=1
  fi
done < <(git -C "$SRC" ls-files -z)
if [ "$saw_fix" != 0 ]; then
  fail "lib/matplotlib/transforms.py is not a tracked file (garbled tree)"
fi
while IFS= read -r -d '' f; do
  # meson's editable loader legitimately keeps subprojects/.wraplock in the
  # source tree (baked in by the image build; recreated on first import).
  if [ "$f" = "subprojects/.wraplock" ]; then
    continue
  fi
  echo "FAIL: untracked non-ignored file: $f" >&2
  bad_tree=1
done < <(git -C "$SRC" ls-files --others -z --exclude-standard)
if [ "$bad_tree" = 1 ]; then
  fail "working tree modified outside lib/matplotlib/transforms.py"
else
  echo "ok: every tracked file except lib/matplotlib/transforms.py is byte-identical to the pinned commit; no stray files"
fi

if ! python3 -c "
import matplotlib
assert matplotlib.__file__.startswith('$SRC'), matplotlib.__file__
" >/dev/null 2>&1; then
  fail "'import matplotlib' does not resolve to the checked-out tree at /app/src"
else
  echo "ok: import matplotlib resolves to $SRC/lib/matplotlib"
fi

# explanation.md deliverable
if [ ! -s /app/explanation.md ]; then
  fail "the deliverable /app/explanation.md is missing or empty"
else
  if ! grep -qi "contains_branch_seperately" /app/explanation.md; then
    fail "/app/explanation.md does not discuss contains_branch_seperately"
  else
    echo "ok: /app/explanation.md exists and discusses the root cause"
  fi
fi

# ---------- 1. golden: the upstream regression test for this bug -------------
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
    echo "ok: /opt/golden/test_transforms.py is the fix-commit regression file (sha $GOLDEN_SHA)"
    cp "$GOLDEN" "$SRC/lib/matplotlib/tests/test_transforms.py"
    run_pytest "golden TestBasicTransform::test_contains_branch" /tmp/golden.out \
      "lib/matplotlib/tests/test_transforms.py::TestBasicTransform::test_contains_branch" || true
  fi
fi

# ---------- 2. the project's own existing transform tests --------------------
echo "== the project's own existing suite (TestBasicTransform subset) =="
run_pytest "existing TestBasicTransform tests" /tmp/own.out \
  "lib/matplotlib/tests/test_transforms.py::TestBasicTransform::test_transform_depth" \
  "lib/matplotlib/tests/test_transforms.py::TestBasicTransform::test_left_to_right_iteration" \
  "lib/matplotlib/tests/test_transforms.py::TestBasicTransform::test_transform_shortcuts" \
  "lib/matplotlib/tests/test_transforms.py::TestBasicTransform::test_affine_simplification" || true

# ---------- 3. the exact issue reproduction command ---------------------------
echo "== issue reproduction =="
if [ "$reward" = 1 ] && ( cd "$SRC" && python3 - <<'EOF' > /tmp/repro.out 2>&1
import matplotlib; matplotlib.use('Agg')
import matplotlib.transforms as mtransforms
from matplotlib.transforms import Transform, Affine2D

class NonAffineForTest(Transform):
    is_affine = False
    output_dims = 2
    input_dims = 2
    def __init__(self, real_trans, *a, **k):
        self.real_trans = real_trans
        super().__init__(*a, **k)
    def transform_non_affine(self, values):
        return self.real_trans.transform(values)
    def transform_path_non_affine(self, path):
        return self.real_trans.transform_path(path)

ta1 = Affine2D().rotate(3.14159 / 2)
ta2 = Affine2D().translate(10, 0)
ta3 = Affine2D().scale(1, 2)
tn1 = NonAffineForTest(Affine2D().translate(1, 2))
tn2 = NonAffineForTest(Affine2D().translate(1, 2))
tn3 = NonAffineForTest(Affine2D().translate(1, 2))
stack2 = ta1 + tn1 + ta2 + ta3
ss = tn1 + ta2 + ta3
blend = mtransforms.BlendedGenericTransform(tn2, stack2)
x, y = blend.contains_branch_seperately(ss)
sx, sy = (tn3 + blend).contains_branch_seperately(ss)
print("blend =", x, y, " composite+blend =", sx, sy)
assert x is False and y is True and sx is False and sy is True
EOF
); then
  echo "ok: the issue reproduction passes"
  sed 's/^/    /' /tmp/repro.out
else
  fail "the issue reproduction still asserts (composite+blend answers wrongly)"
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