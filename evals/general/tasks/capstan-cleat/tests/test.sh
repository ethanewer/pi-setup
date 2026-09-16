#!/bin/bash
# Verifier for capstan-cleat: an upstream-clone debugging task on
# matplotlib/matplotlib.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# Axes.axline renders a line given a very small non-zero slope (|slope| <=
# 1e-8) as perfectly horizontal, because AxLine.get_transform decides the
# line is horizontal with np.isclose(slope, 0) whose default atol snaps such
# slopes to zero. The agent must AUTHOR its own reproduction (/app/repro.sh,
# driving the project's own `python3 -m pytest` runner), get it failing on
# the buggy tree, then apply a minimal source fix (only an exactly-zero slope
# may be horizontal) so that the reproduction, the project's own regression
# test for this bug, the project's own existing tests, and this task's hidden
# cases all pass.
#
# Structure:
#   0. provenance: HEAD is the pinned parent commit, the upstream fix commit
#      is not reachable, exactly one commit exists, every tracked file except
#      lib/matplotlib/lines.py is byte-identical to the pinned commit, no
#      untracked non-ignored files except the meson subprojects/.wraplock,
#      `import matplotlib` resolves to the checked-out tree, the deliverables
#      exist and the buggy np.isclose(slope pattern is gone from the fixed
#      source;
#   1. the agent's reproduction against the PRE-FIX tree (rendering source
#      restored to the pinned version): it must FAIL and print a failing
#      pytest run;
#   2. the agent's reproduction against the repaired tree: it must PASS;
#   3. the project's own upstream regression test for this bug (the fix-
#      commit test_lines.py, extracted at build time into /opt/golden):
#      test_axline_small_slope must pass against the repaired tree;
#   4. a subset of the project's own existing axline/line tests (parent
#      files): they must pass, proving the fix broke nothing else;
#   5. four authored hidden cases reach the same code path from inputs the
#      upstream test never uses: slope -1e-14 (negative tilt), slope 5e-9
#      (different magnitude, still inside the snap window), slope 1e-14
#      anchored at (1, 2), and a slope-exactly-0 constraint case. The three
#      small-slope cases must FAIL on the pre-fix tree and all four must PASS
#      on the repaired tree; at least two of the four must discriminate
#      (fail pre-fix);
#   6. end state: the tree is dirty in lib/matplotlib/lines.py only.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
# Never trust a reward file left in the image by an earlier phase or by the
# agent itself: the reward below is computed by THIS run and written at the end.
rm -f /logs/verifier/reward.txt
reward=1

SRC=/app/src
PARENT_SHA=7722dead68f8de43480f1f58386d03396bd5d58e
FIX_SHA=e90952ffac668bd5115c4009bf20dd6e595c3cd5
GOLDEN=/opt/golden/test_lines.py
GOLDEN_SHA=86a8a8c942cb715ca9138a32099a0ccdf30c5d06d846028f60c9a829b42745a7
FIXFILE=lib/matplotlib/lines.py

export PYTHONDONTWRITEBYTECODE=1

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

run_pytest () {  # run_pytest LABEL OUT ...args  -- runs pytest in $SRC on the agent tree
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
# the bug lives in (lib/matplotlib/lines.py, which the agent must locate
# itself) must be byte-identical to the pinned commit's blob. Symlinked
# tracked files (mpl-data image symlinks) are hashed by their link target.
bad_tree=0
saw_fix=1
while IFS= read -r -d '' f; do
  if [ "$f" = "$FIXFILE" ]; then
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
  fail "lib/matplotlib/lines.py is not a tracked file (garbled tree)"
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
  fail "working tree modified outside lib/matplotlib/lines.py"
else
  echo "ok: every tracked file except lib/matplotlib/lines.py is byte-identical to the pinned commit; no stray files"
fi

if ! python3 -c "
import matplotlib
assert matplotlib.__file__.startswith('$SRC'), matplotlib.__file__
" >/dev/null 2>&1; then
  fail "'import matplotlib' does not resolve to the checked-out tree at /app/src"
else
  echo "ok: import matplotlib resolves to $SRC/lib/matplotlib"
fi

# the fix must actually be present in the source: the buggy default-atol
# snap must be gone. `np.isclose(slope, 0)` with numpy's default atol=1e-8
# is the bug; an exact-equality comparison (or an isclose call that no longer
# snaps at the default tolerance) is what the behavioral checks above prove.
if grep -nE 'np\.isclose\(slope, 0\)' "$SRC/$FIXFILE" 2>/dev/null; then
  fail "the buggy np.isclose(slope, 0) snapping pattern is still present in lib/matplotlib/lines.py"
else
  echo "ok: the default-atol np.isclose(slope, 0) snap is gone from the source"
fi
if [ -z "$(git -C "$SRC" diff -- "$FIXFILE" 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: lib/matplotlib/lines.py differs from the pinned commit"
fi

if [ ! -f /app/repro.sh ]; then
  fail "the deliverable /app/repro.sh does not exist"
elif [ ! -x /app/repro.sh ]; then
  fail "the deliverable /app/repro.sh is not executable"
else
  echo "ok: /app/repro.sh exists and is executable"
fi
if [ -f /app/repro.sh ] && ! grep -q 'pytest' /app/repro.sh; then
  fail "/app/repro.sh never invokes the project's own test runner (\`pytest\`)"
else
  echo "ok: /app/repro.sh drives the project's own test runner"
fi
if [ ! -s /app/explanation.md ]; then
  fail "the deliverable /app/explanation.md is missing or empty"
else
  if ! grep -qi "axline" /app/explanation.md; then
    fail "/app/explanation.md does not discuss axline"
  else
    echo "ok: /app/explanation.md exists and discusses the root cause"
  fi
fi

# ---------- pre-fix tree: restore the rendering source to the parent blob ----
# Snapshot the agent's fixed file so it can be restored afterwards.
if [ -f "$SRC/$FIXFILE" ]; then
  cp "$SRC/$FIXFILE" /tmp/agent-lines.py 2>/dev/null || true
fi
if [ -s /tmp/agent-lines.py ]; then
  git -C "$SRC" checkout HEAD -- "$FIXFILE" >/dev/null 2>&1 || true
fi

# ---------- 1. agent repro against the PRE-FIX tree (must fail) ---------------
echo "== agent reproduction against the pre-fix tree =="
if [ -f /app/repro.sh ] && [ -x /app/repro.sh ] && [ -s /tmp/agent-lines.py ]; then
  if bash /app/repro.sh > /tmp/repro-prefix.out 2>&1; then
    echo "FAIL: the agent's reproduction PASSED on the pre-fix tree; it does not detect the bug" >&2
    reward=0
  else
    if grep -qEi 'failed|AssertionError' /tmp/repro-prefix.out; then
      echo "ok: the agent reproduction fails on the pre-fix tree with a failing pytest run"
    else
      echo "FAIL: the agent reproduction failed on the pre-fix tree but without a failing pytest run; it is not a behavioural reproduction" >&2
      tail -20 /tmp/repro-prefix.out | sed 's/^/    /' >&2
      reward=0
    fi
  fi
else
  echo "FAIL: cannot run the agent reproduction against the pre-fix tree (missing /app/repro.sh or fixed source snapshot)" >&2
  reward=0
fi

# ---------- 1b. hidden cases against the PRE-FIX tree (must discriminate) ------
echo "== hidden cases against the pre-fix tree (must fail) =="
prefail=0
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  for f in "$case"test_*.py; do
    [ -f "$f" ] || continue
    n_hidden=$((n_hidden + 1))
    name=$(basename "$(dirname "$f")")/$(basename "$f")
    if python3 "$f" > /tmp/hidden-prefix.out 2>&1; then
      echo "ok: hidden case $name passes on the pre-fix tree (non-discriminating, expected for the zero-slope constraint case)"
    else
      prefail=$((prefail + 1))
      echo "ok: hidden case $name FAILS on the pre-fix tree as required"
    fi
  done
done
if [ "$prefail" -lt 2 ]; then
  echo "FAIL: only $prefail of the hidden cases fail on the pre-fix tree; the hidden cases do not discriminate" >&2
  reward=0
else
  echo "ok: $prefail hidden cases fail on the pre-fix tree"
fi

# ---------- restore the agent's fixed tree ------------------------------------
if [ -s /tmp/agent-lines.py ]; then
  cp /tmp/agent-lines.py "$SRC/$FIXFILE"
fi

# ---------- 2. agent repro against the repaired tree (must pass) ---------------
echo "== agent reproduction against the repaired tree =="
if [ -f /app/repro.sh ] && [ -x /app/repro.sh ]; then
  if bash /app/repro.sh > /tmp/repro-fixed.out 2>&1; then
    if grep -q 'passed' /tmp/repro-fixed.out; then
      echo "ok: the agent reproduction passes on the repaired tree"
    else
      echo "FAIL: the agent reproduction passed on the repaired tree but without a passing pytest run" >&2
      reward=0
    fi
  else
    echo "FAIL: the agent reproduction failed on the repaired tree" >&2
    tail -30 /tmp/repro-fixed.out | sed 's/^/    /' >&2
    reward=0
  fi
fi

# ---------- 3. golden: the upstream regression test for this bug --------------
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
    echo "ok: /opt/golden/test_lines.py is the fix-commit regression file (sha $GOLDEN_SHA)"
    cp "$GOLDEN" /tmp/test_lines_golden.py
    run_pytest "golden test_axline_small_slope" /tmp/golden.out \
      "/tmp/test_lines_golden.py::test_axline_small_slope" || true
  fi
fi

# ---------- 4. the project's own existing axline/line tests -------------------
echo "== the project's own existing axline/line tests =="
run_pytest "existing axline/line tests" /tmp/own.out \
  "lib/matplotlib/tests/test_axes.py::test_axline_args" \
  "lib/matplotlib/tests/test_lines.py::test_axline_setters" \
  "lib/matplotlib/tests/test_lines.py::test_segment_hits" \
  "lib/matplotlib/tests/test_lines.py::test_invalid_line_data" \
  "lib/matplotlib/tests/test_lines.py::test_linestyle_variants" || true

# ---------- 5. hidden cases against the repaired tree (must pass) -------------
echo "== hidden cases against the repaired tree =="
hidpass=0
staged_zero="$SRC/lib/matplotlib/tests/test_zz_zero_hidden.py"
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  for f in "$case"test_*.py; do
    [ -f "$f" ] || continue
    name=$(basename "$(dirname "$f")")/$(basename "$f")
    if [ "$(basename "$(dirname "$f")")" = "case-zero-slope" ]; then
      # The zero-slope constraint is a core correctness requirement of the
      # task, so it must not depend on what the agent chose to put in its
      # own reproduction. Run it through the project's own pytest runner
      # with the file staged inside the tree, so matplotlib's testing
      # conftest (filterwarnings = error) applies: a "remove the zero
      # handling" cheat that lets slope=0 fall into the general intersection
      # math divides by zero, and that RuntimeWarning is raised as an error;
      # every honest formulation of the horizontal test is warning-free.
      if ! cp "$f" "$staged_zero"; then
        fail "could not stage the zero-slope hidden case"
        continue
      fi
      zero_out=/tmp/hidden-zero-fixed.out
      if ( cd "$SRC" && python3 -m pytest "$staged_zero" -p no:cacheprovider -q > "$zero_out" 2>&1 ); then
        rm -f "$staged_zero"
        hidpass=$((hidpass + 1))
        echo "ok: hidden case $name (via the project's own pytest runner)"
        tail -1 "$zero_out" | sed 's/^/    /'
      else
        rm -f "$staged_zero"
        fail "hidden case $name"
        tail -15 "$zero_out" | sed 's/^/    /' >&2
      fi
    else
      out="/tmp/hidden-fixed-${hidpass}.out"
      if python3 "$f" > "$out" 2>&1; then
        hidpass=$((hidpass + 1))
        echo "ok: hidden case $name"
        tail -1 "$out" | sed 's/^/    /'
      else
        fail "hidden case $name"
        tail -15 "$out" | sed 's/^/    /' >&2
      fi
    fi
  done
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi
if [ "$hidpass" -ne "$n_hidden" ]; then
  fail "$((n_hidden - hidpass)) hidden case(s) failed on the repaired tree"
fi

# ---------- 6. tree clean again after the verifier's own runs ----------------
post=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
extra=$(printf '%s\n' "$post" |
        grep -v '^ M lib/matplotlib/lines.py$' |
        grep -v '^?? subprojects/.wraplock$' || true)
if [ -n "$extra" ]; then
  echo "FAIL: the working tree is not clean after the verifier runs (only lib/matplotlib/lines.py should differ):" >&2
  printf '%s\n' "$extra" | head -10 | sed 's/^/    /' >&2
  reward=0
else
  echo "ok: tree restored after all verifier runs"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0