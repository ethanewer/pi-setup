#!/bin/bash
# Verifier for chainplate-current: an upstream-clone debugging task on mypy.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# with --allow-redefinition enabled, mypy aborts with an INTERNAL ERROR (exit
# 2) on an ordinary module whose function declares `global <name>` for a
# module-level variable that still carries a partial type (e.g. `x = []`).
# The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, mypy/checker.py holds a non-empty
#      diff, the overlaid regression-test data is byte-identical to the
#      upstream regression test, and nothing else in the repository changed);
#   1. runs the CLI reproduction and requires exit 1 with exactly the "need
#      type annotation" diagnostic and no INTERNAL ERROR anywhere;
#   2. requires the project's own regression case
#      testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2
#      (from the fix commit, carried in /opt/golden and overlaid at build
#      time) to pass;
#   3. requires the project's whole checker suite
#      (mypy/test/testcheck.py, ~8000 data-driven cases) to pass from the
#      repaired tree, proving the fix broke nothing else;
#   4. runs three authored hidden cases through the repaired tree's own mypy
#      -- all inputs that crash (INTERNAL ERROR, exit 2) at the parent commit
#      and must check normally (exit 1, exactly the expected diagnostics) at
#      the fix: a `global` statement naming two partial-typed variables, a
#      partial-typed dict with a subscript assignment after `global`, and a
#      `global` declaration nested in an inner function.
#
# All pytest invocations clear mypy's own `-nauto` addopts (`-o addopts=""`)
# so pytest-xdist cannot fan out to one worker per CPU inside this one-CPU
# container. The full suite takes ~4 minutes at 1 CPU.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=1730c9535e464be8a1eee4d74f74156d75a6c0b2
FIX_SHA=3f0c355b7b5fbce50fc192a697bbe4f214e01253
GOLDEN=/opt/golden/check-inference.test
DATA=test-data/unit/check-inference.test

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0b. interpreter provenance ---------------------------------------------
# The verifier drives the project through the container's python3. Pin that
# interpreter (hash of /usr/local/bin/python3 as measured at image build time
# on bench-base:python-3.12) and make the tree's own mypy report the pinned
# revision, so a replaced or wrapped interpreter that replays canned output
# (and thereby hides the still-unfixed crash) is detected before any check
# runs. The honest oracle never touches the interpreter, so it is unaffected.
echo "== interpreter provenance =="
pybin=$(command -v python3)
if [ "$pybin" != "/usr/local/bin/python3" ]; then
  fail "python3 resolves to $pybin, expected /usr/local/bin/python3"
else
  echo "ok: python3 resolves to /usr/local/bin/python3"
fi
pin=0e6475dfda68a9b2d93501449fc47593ca169010e8f4881577b97463fd0c1263
have=$(sha256sum < "$pybin" | cut -d' ' -f1)
if [ "$have" != "$pin" ]; then
  fail "python3 binary hash $have does not match the pinned interpreter $pin"
else
  echo "ok: python3 is byte-identical to the pinned interpreter"
fi
if ! ( cd "$SRC" && python3 -m mypy --version 2>/dev/null ) | grep -q "1730c9535e464be8a1eee4d74f74156d75a6c0b2"; then
  fail "python3 -m mypy --version does not report the pinned tree revision"
else
  echo "ok: the tree's mypy reports the pinned revision 1730c9535...."
fi

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

if [ -z "$(git -C "$SRC" diff HEAD -- mypy/checker.py 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: mypy/checker.py differs from the pinned commit"
fi

tree_golden=$(sha256sum < "$SRC/$DATA" 2>/dev/null | cut -d' ' -f1)
golden_sha=$(sha256sum < "$GOLDEN" 2>/dev/null | cut -d' ' -f1)
if [ -n "$golden_sha" ] && [ "$tree_golden" = "$golden_sha" ]; then
  echo "ok: $DATA is byte-identical to the upstream regression test data"
else
  fail "$DATA was altered (tree ${tree_golden:-missing} vs golden ${golden_sha:-missing})"
fi

# Accept the fix and the overlaid regression data in any index state (staged
# or unstaged): only the path set matters, plus the absence of untracked files.
changed=$(git -C "$SRC" diff HEAD --name-only 2>/dev/null || true)
untracked=$(git -C "$SRC" status --porcelain 2>/dev/null | grep -c '^??' || true)
expected_files="mypy/checker.py"$'\n'"$DATA"
if [ "$changed" = "$expected_files" ] && [ "${untracked:-0}" = "0" ]; then
  echo "ok: working tree differs from the pinned commit only in the fix and the overlaid regression data"
else
  fail "unexpected working-tree differences:"
  printf '%s\n' "$changed" | head -10 | sed 's/^/    /' >&2
  [ "${untracked:-0}" = "0" ] || echo "    (untracked files present)" >&2
fi

# ---------- 1. CLI reproduction ----------------------------------------------
echo "== CLI reproduction =="
printf 'x = []\n\ndef f() -> None:\n    global x\n    x\n' > /tmp/repro.py
( cd "$SRC" && python3 -m mypy --no-incremental --allow-redefinition \
      --cache-dir=/tmp/verifier-cache /tmp/repro.py > /tmp/repro.out 2>&1 )
rc=$?
if [ "$rc" -eq 1 ] \
   && ! grep -q "INTERNAL ERROR" /tmp/repro.out \
   && grep -qF 'error: Need type annotation for "x" (hint: "x: list[<type>] = ...")  [var-annotated]' /tmp/repro.out \
   && grep -qF "Found 1 error in 1 file (checked 1 source file)" /tmp/repro.out; then
  echo "ok: reproduction exits 1 with the need-annotation diagnostic, no INTERNAL ERROR"
else
  fail "CLI reproduction did not behave as expected (exit $rc)"
  cat /tmp/repro.out | sed 's/^/    /' >&2
fi

# ---------- 2. golden regression test ----------------------------------------
echo "== golden regression test =="
if ( cd "$SRC" && python3 -m pytest mypy/test/testcheck.py \
       -k "testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2" \
       -q -o addopts="" > /tmp/golden.out 2>&1 ); then
  if grep -q "1 passed" /tmp/golden.out; then
    echo "ok: golden case passes: testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2"
  else
    fail "golden pytest exited 0 but did not report 1 passed"
    tail -6 /tmp/golden.out | sed 's/^/    /' >&2
  fi
else
  fail "golden case FAILED: testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2"
  tail -6 /tmp/golden.out 2>/dev/null | sed 's/^/    /' >&2 || true
fi

# ---------- 3. the project's own checker suite ---------------------------------
echo "== the project's own checker suite (mypy/test/testcheck.py, ~8000 cases) =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && python3 -m pytest mypy/test/testcheck.py \
         -q -o addopts="" > /tmp/suite.out 2>&1 ); then
    echo "ok: full checker suite exits 0: $(grep -E '[0-9]+ (passed|failed)' /tmp/suite.out | tail -1)"
  else
    fail "the project's own checker suite is not fully green"
    tail -8 /tmp/suite.out | sed 's/^/    /' >&2
  fi
else
  echo "skipped (already failed a previous check)"
fi

# ---------- 4. authored hidden cases -----------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  cname=$(basename "$case")
  input="$case/input.py"
  expected="$case/expected.txt"
  [ -f "$input" ] || { fail "hidden case $cname has no input.py"; continue; }
  if [ ! -f "$expected" ]; then
    fail "hidden case $cname has no expected.txt"
    continue
  fi
  cp "$input" "/tmp/hc_${cname}.py"
  ( cd "$SRC" && python3 -m mypy --no-incremental --allow-redefinition \
        --cache-dir="/tmp/hc-cache-${cname}" "/tmp/hc_${cname}.py" > "/tmp/hc_out_${cname}.txt" 2>&1 )
  rc=$?
  if [ "$rc" -eq 1 ] \
     && ! grep -q "INTERNAL ERROR" "/tmp/hc_out_${cname}.txt" \
     && diff -u "$expected" "/tmp/hc_out_${cname}.txt" > "/tmp/hc_diff_${cname}.txt" 2>&1; then
    echo "ok: hidden case $cname (exit 1, exact expected diagnostics)"
  else
    fail "hidden case $cname (exit $rc)"
    cat "/tmp/hc_out_${cname}.txt" 2>/dev/null | sed 's/^/    output: /' >&2 || true
    cat "/tmp/hc_diff_${cname}.txt" 2>/dev/null | sed 's/^/    diff: /' >&2 || true
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0