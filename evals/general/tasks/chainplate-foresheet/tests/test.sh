#!/bin/bash
# Verifier for chainplate-foresheet: an upstream-clone debugging task on
# sharkdp/fd. The agent must fix, in the real checkout at /app/src, a real
# upstream bug: a --full-path search whose working directory is removed
# mid-search panics the whole process (exit 101) instead of finishing,
# skipping, or reporting the problem.
#
# The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, exactly
#      one commit object, no tracked file deleted, the only modified tracked
#      files are project source files under src/ with at least one such
#      modification present, no new files under src/);
#   1. builds the tree with the project's own cargo (must compile);
#   2. runs the upstream regression test for this bug (the TEST MODULE
#      extracted into /opt/golden/tests-module.rs at image build time,
#      together with the search_str_for_entry helper signature it uses)
#      against the agent's tree when the tree can accept it;
#      alternative-but-correct fix shapes are carried by the CLI cases in
#      step 4 (see comments below);
#   3. runs the project's own full test suite (unit + integration), proving
#      the fix broke nothing else (the 1-CPU timing-sensitive test_exec_nulls
#      is skipped, as documented in the instruction);
#   4. runs three authored hidden CLI cases that exercise the same code path
#      from inputs the upstream regression test does not use: --full-path
#      with the cwd removed mid-walk in default print mode, -x exec mode and
#      -X exec-batch mode, each with --show-errors, asserting a graceful
#      outcome (exit 1 with the filesystem error reported, or exit 0 with
#      matches produced) and never a panic.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=7027d45303b412be6fa9c09d689cc6276748fb38
FIX_SHA=d3a500af7aee3a9f099b09e1831da3fc39980c61
GOLDEN=/opt/golden/tests-module.rs
FD_BIN="$SRC/target/debug/fd"
GOLDEN_TEST_NAME=full_path_search_returns_error_for_invalid_cwd

export PATH=/opt/cargo/bin:$PATH

run_cargo () {  # run_cargo LABEL OUT ...args  (cwd = SRC)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && cargo "$@" > "$out" 2>&1 ); then
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

# Normalize git status --porcelain v1 lines into (status, path) pairs.
saw_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  st=${line:0:2}
  path=${line:3}
  case "$st" in
    " M"|"M "|"MM") # modified tracked file
      case "$path" in
        src/*) saw_mod=1 ;;
        *) echo "FAIL: a tracked file outside src/ was modified (including any test file): $line" >&2; bad_tree=1 ;;
      esac
      ;;
    " D"|"D "|"MD"|"AD"|"DD") echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "??") # untracked
      case "$path" in
        src/*) echo "FAIL: a new file was added inside src/: $line" >&2; bad_tree=1 ;;
        *) : ;; # untracked files outside src/ are allowed (agent scratch)
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2; reward=0
else
  echo "ok: at least one source file under src/ is modified"
fi

if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden file missing from image" >&2; reward=0
elif ! grep -q "fn $GOLDEN_TEST_NAME" "$GOLDEN"; then
  echo "FAIL: golden file does not contain the upstream regression test" >&2; reward=0
else
  echo "ok: golden regression-test source present in image"
fi

# ---------- 1. the agent's tree must build -----------------------------------
echo "== cargo build =="
run_cargo "cargo build of the repaired tree" /tmp/cargo-build.out build || true
if [ ! -x "$FD_BIN" ]; then
  echo "FAIL: no fd binary at $FD_BIN (build did not produce it)" >&2; reward=0
fi

# ---------- 2. golden: the project's own regression test ---------------------
# The regression test full_path_search_returns_error_for_invalid_cwd exists
# only at the upstream fix commit (it references the new search_str_for_entry
# helper), so this checkout does not have it. /opt/golden/tests-module.rs is
# that TEST MODULE alone, extracted from the fix commit at build time; the
# fixed implementation source is never shipped in the image. Three situations:
#   * the agent's fix is shaped like the upstream one (it added the helper or
#     the test) -> run the test through the project's own test runner and
#     require it to pass;
#   * the agent's fix is an alternative shape -> the test cannot compile
#     against it; the behavioural contract is carried by the hidden CLI cases
#     in step 4, and this step is logged and skipped;
#   * the run compiles but the test fails -> hard failure.
echo "== golden regression test ($GOLDEN_TEST_NAME against the repaired tree) =="
# Extract the upstream test function source from the golden file.
awk '
  /fn full_path_search_returns_error_for_invalid_cwd\(\) \{/ { on=1 }
  on { print }
  on && /^    \}$/ { exit }
' "$GOLDEN" > /tmp/golden-test-fn.txt 2>/dev/null || true
if [ ! -s /tmp/golden-test-fn.txt ]; then
  echo "FAIL: could not extract the regression test from the golden file" >&2; reward=0
else
  if grep -q "fn $GOLDEN_TEST_NAME" "$SRC/src/walk.rs" 2>/dev/null; then
    # The agent's tree carries a test with the upstream name: run it.
    run_cargo "project regression test $GOLDEN_TEST_NAME (present in the agent's walk.rs)" /tmp/golden-test.out \
      test "$GOLDEN_TEST_NAME" || true
  elif grep -q "fn search_str_for_entry" "$SRC/src/walk.rs" 2>/dev/null; then
    # Upstream-shaped helper present but no test: the golden file already IS
    # the upstream test module (starting at its #[cfg(test)] attribute);
    # rename the module, append it to a temporary copy of the agent's
    # walk.rs, run the test, restore.
    cp "$GOLDEN" /tmp/golden-module.rs
    sed -i 's/^mod tests {$/mod golden_chainplate_check {/' /tmp/golden-module.rs
    if grep -q "mod golden_chainplate_check {" /tmp/golden-module.rs; then
      cp "$SRC/src/walk.rs" /tmp/walk.rs.agent
      cat /tmp/golden-module.rs >> "$SRC/src/walk.rs"
      set +e
      ( cd "$SRC" && cargo test "$GOLDEN_TEST_NAME" ) > /tmp/golden-inject.out 2>&1
      injrc=$?
      set -e
      cp /tmp/walk.rs.agent "$SRC/src/walk.rs"   # restore the agent's file
      if [ "$injrc" -eq 0 ]; then
        echo "ok: project regression test $GOLDEN_TEST_NAME (injected from /opt/golden)"
      elif grep -qE "^error(\[|:)" /tmp/golden-inject.out 2>/dev/null; then
        # The injected upstream test does not compile against this fix shape
        # (different helper signature); the CLI cases in step 4 carry the
        # behavioural contract. Log, do not fail.
        echo "note: golden test does not compile against this fix shape (alternative implementation); relying on hidden CLI cases"
        echo "    $(grep -m1 -E '^error' /tmp/golden-inject.out | sed 's/^/    /')"
      else
        echo "FAIL: project regression test $GOLDEN_TEST_NAME failed against the repaired tree" >&2
        tail -30 /tmp/golden-inject.out | sed 's/^/    /' >&2
        reward=0
      fi
    else
      echo "note: could not reconstruct the golden test module; relying on hidden CLI cases"
    fi
  else
    echo "note: the upstream-shaped helper is not present (alternative fix shape); relying on hidden CLI cases"
  fi
fi

# ---------- 3. the project's own existing test suite --------------------------
# The trial container is capped at 1 CPU (cpus = 1 in task.toml). fd's own
# integration test `test_exec_nulls` interleaves --exec output with NUL
# separators and is timing-sensitive when the parallel directory walk outruns
# the exec worker threads under CPU starvation: it fails spuriously on a 1-CPU
# quota (measured in the sibling fd task capstan-brackish) regardless of this
# bug or fix, and does not touch the full-path/working-directory code path.
# The whole suite minus THAT ONE test is asserted below; any other failure is
# a real regression.
echo "== the project's own full test suite (unit + integration), test_exec_nulls skipped (1-CPU timing race) =="
run_cargo "full project test suite" /tmp/full-suite.out \
  test -- --skip test_exec_nulls || true

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  script="${case}run.sh"
  [ -f "$script" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if bash "$script" > "$out" 2>&1; then
    echo "ok: hidden case $name"
    grep -E "^ok:|exit status|remove" "$out" | sed 's/^/    /' | head -4
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

# Release the shared 400k-file tree the hidden cases built.
/bin/rm -rf /tmp/fd-case-big 2>/dev/null || true

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0