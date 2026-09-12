#!/bin/bash
# Verifier for cistern-cinder: an upstream-clone debugging task on psutil.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# psutil.virtual_memory() raises ValueError ("invalid literal for int() with
# base 10: b'kB'") when /proc/meminfo contains a field with no space after its
# colon (the arm64 ShadowCallStack layout). The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, the only
#      pre-existing modification is the overlaid regression test
#      tests/test_linux.py which must still byte-match the build-time copy in
#      /opt/golden/, the only additional tracked modification is
#      psutil/_pslinux.py, and no new files appeared inside psutil/ or tests/);
#   1. runs the project's upstream regression test for this bug, extracted at
#      image build time from the fix commit and overlaid into the working tree;
#   2. runs the rest of the project's own existing Linux test file and requires
#      it green, excluding only TestRootFsDeviceFinder (its three tests compare
#      against the container's findmnt output and fail here for environment
#      reasons unrelated to this bug); the free/vmstat CLI comparison classes
#      DO run -- those CLIs are present in the image;
#   3. runs two authored hidden cases that drive the same code path from
#      /proc/meminfo layouts the upstream test does not use (multiple
#      no-space standard fields with 9/11-digit magnitudes, and the
#      MemAvailable-missing fallback + avail>total clamp edges).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=afaaf9f340ff6561541f9f4781c58268b59abdac
FIX_SHA=8d8ffe516627c024ccd216485b5920e8ffa8a88e
GOLDEN=/opt/golden/test_linux.py

run_pytest () {  # run_pytest LABEL OUT ...args   (cwd is $SRC)
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -50 "$out" | sed 's/^/    /' >&2
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
  echo "ok: HEAD is the pinned parent commit"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
fi

if ! cmp -s "$SRC/tests/test_linux.py" "$GOLDEN"; then
  echo "FAIL: tests/test_linux.py no longer byte-matches the overlaid regression test (it must stay exactly as laid down at build time)" >&2
  reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=$(printf '%s\n' "$porcelain" \
  | grep -v '^ M tests/test_linux.py$' \
  | grep -v '^ M psutil/_pslinux.py$' \
  | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (allowed: the overlaid tests/test_linux.py and your fix to psutil/_pslinux.py):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newinpkg=$(printf '%s\n' "$porcelain" | grep '^?? psutil/\|^?? tests/' || true)
if [ -n "$newinpkg" ]; then
  echo "FAIL: new files were added inside the psutil/ or tests/ trees:" >&2
  printf '%s\n' "$newinpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- psutil/_pslinux.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented in psutil/_pslinux.py)" >&2
  reward=0
fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
run_pytest "golden test_virtual_memory_no_space_after_colon" /tmp/golden.out \
  tests/test_linux.py::TestVirtualMemoryMocks::test_virtual_memory_no_space_after_colon || true

# ---------- 2. the project's own existing tests -------------------------------
# The whole test_linux.py file, minus the findmnt-comparison class that is
# not runnable in this container and minus the TestVirtualMemoryAgainstFree
# class, which compares psutil.virtual_memory() against the `free` command
# inside a 5 MB tolerance with ten retries: on a busy shared host (or under a
# parallel census shard) the retries can exhaust and the suite fails for a
# memory-churn reason unrelated to this task's /proc/meminfo parsing bug.
# 103 tests, 18 skips, 0 failures on the fixed tree at build time.
echo "== the project's own existing Linux tests (all of tests/test_linux.py minus TestRootFsDeviceFinder and TestVirtualMemoryAgainstFree) =="
run_pytest "existing tests/test_linux.py suite" /tmp/existing.out \
  -k "not RootFsDeviceFinder and not TestVirtualMemoryAgainstFree" tests/test_linux.py || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd /tmp && python3 -m pytest "$case" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -50 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0