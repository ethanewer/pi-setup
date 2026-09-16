#!/bin/bash
# Verifier for capstan-brackish: an upstream-clone debugging task on
# sharkdp/fd. The agent must fix, in the real checkout at /app/src, a real
# upstream bug: an out-of-range '@' Unix timestamp given to --changed-before /
# --changed-within panics the process with an arithmetic-overflow panic
# instead of being rejected like any other unparseable date.
#
# The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, exactly
#      one commit object, no tracked file deleted, the only modified tracked
#      files are project source files under src/ with at least one such
#      modification present, no new files under src/, and the project's own
#      regression test for this bug is still byte-identical to the upstream
#      copy extracted at image build time into /opt/golden/);
#   1. builds the tree with the project's own cargo (must compile);
#   2. runs the project's own regression test for this bug via the project's
#      own test runner (cargo test out_of_range_unix_timestamp_is_rejected);
#   3. runs the project's own full test suite (unit + integration), proving
#      the fix broke nothing else;
#   4. runs three authored hidden CLI cases that exercise the same code path
#      from inputs the upstream regression test does not use: --changed-before
#      with the out-of-range timestamp @9223372036854775808, --changed-within
#      with @18446744073709551614, and a guard that the huge but in-range
#      timestamp @9223372036854775807 keeps working normally.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=fb0426fed164c5fa9cd04b5e4aa8d8c375efa1d0
FIX_SHA=5becb9d52cb532c35b68421075e4d8ee8d6c77cd
GOLDEN=/opt/golden/time.test.txt
FD_BIN="$SRC/target/debug/fd"

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
# Lines look like " M src/filter/time.rs" (worktree-modified), "M  ..."
# (staged), " D ..."/"D  ..." (deleted), "?? path" (untracked). Both the
# staged and unstaged variants of a modification are accepted, because a
# correct agent may `git add` its fix without committing.
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

# The project's own regression test for this bug must be present and unchanged
# (its source lives inside src/filter/time.rs, the very file the fix touches,
# so it is compared against the fix-commit golden copy extracted at image
# build time. The golden file contains ONLY the test function -- its
# '#[test]' attribute line and body -- never the surrounding fixed source).
# The attribute line is included in the comparison so that an agent cannot
# silently neutralise the test (e.g. by turning #[test] into #[ignore] or by
# deleting the attribute) instead of fixing the bug.
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden file missing from image" >&2; reward=0
else
  extract_test () {  # extract_test FILE  ->  awk-printed test fn (with its #[test] attribute)
    awk '
      /fn out_of_range_unix_timestamp_is_rejected\(\) \{/ { if (prev ~ /#\[/) print prev; on=1 }
      on { print }
      on && /^    \}$/ { exit }
      { prev=$0 }
    ' "$1"
  }
  if diff -q <(extract_test "$GOLDEN" | sed 's/[[:space:]]*$//') \
             <(extract_test "$SRC/src/filter/time.rs" | sed 's/[[:space:]]*$//') >/dev/null 2>&1; then
    echo "ok: the regression test out_of_range_unix_timestamp_is_rejected is intact in the tree"
  else
    echo "FAIL: the project's own regression test for this bug was modified, removed, or its #[test] attribute was tampered with" >&2
    echo "    expected (from fix-commit golden):" >&2
    extract_test "$GOLDEN" | sed 's/^/    /' | head -8 >&2
    reward=0
  fi
fi

# ---------- 1. the agent's tree must build -----------------------------------
echo "== cargo build =="
run_cargo "cargo build of the repaired tree" /tmp/cargo-build.out build || true
if [ ! -x "$FD_BIN" ]; then
  echo "FAIL: no fd binary at $FD_BIN (build did not produce it)" >&2; reward=0
fi

# ---------- 2. golden: the project's own regression test ----------------------
echo "== golden regression test (cargo test out_of_range_unix_timestamp_is_rejected) =="
run_cargo "project regression test out_of_range_unix_timestamp_is_rejected" /tmp/golden-test.out \
  test out_of_range_unix_timestamp_is_rejected || true

# ---------- 3. the project's own existing test suite --------------------------
# The trial container is capped at 1 CPU (cpus = 1 in task.toml). fd's own
# integration test `test_exec_nulls` interleaves --exec output with NUL
# separators and is timing-sensitive when the parallel directory walk
# outruns the exec worker threads under CPU starvation: it fails
# spuriously on a 1-CPU quota (measured: fails ~always under `--cpus=1`,
# passes on multi-core) regardless of the time-filter bug or fix. It does
# not touch the time-filter code path at all. The whole suite minus that
# ONE test is asserted below; any other failure is a real regression.
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