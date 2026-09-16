#!/bin/bash
# Verifier for spile-wharf: an upstream-clone debugging task on psutil.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# psutil.swap_memory() crashes with ValueError ("invalid literal for int()
# with base 10: b'kB'") whenever /proc/meminfo carries a field printed with
# no space after its colon. The verifier:
#   0. asserts tree provenance (HEAD still at the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, the only
#      tracked differences are the minimal source fix and the overlaid
#      regression test, the overlaid test file is byte-identical to the
#      upstream regression test, the installed psutil resolves into /app/src,
#      and no interpreter-squatting helper was planted);
#   1. runs the agent's own reproduction script /app/reproduce.py against a
#      pristine PRE-FIX copy of the code (read-only /opt/pristine, selected
#      via PYTHONPATH) and requires it to crash with the genuine ValueError —
#      this is what proves the reproduction actually demonstrates the bug;
#      then runs the same script against the agent's REPAIRED tree and
#      requires exit 0 with consistent, printed swap figures;
#   2. restores the upstream regression test from /opt/golden and runs the
#      project's own test SUITE for the affected area (the full
#      TestSwapMemory class including the regression test, plus
#      TestVirtualMemoryAgainstFree::test_total) against the repaired tree;
#   3. runs three authored hidden cases with meminfo contents the upstream
#      regression test does not use, asserting exact total/free/used/percent.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=5ec16ad4d887c069f6b758fd0659fb6bc9b47f7d
FIX_SHA=d46726028ac01e27e052ec60371951e789d2b101
GOLDEN=/opt/golden/test_linux.py
GOLDEN_SHA=ed21926713e0b2e4c7aef75e2889d9792675818252eeb89ec0f7b6b0bda80754
REPRO=/app/reproduce.py
RUNDIR=/tmp/vrun

rm -rf "$RUNDIR"
mkdir -p "$RUNDIR"

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
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

if [ -z "$(git -C "$SRC" diff -- psutil/_pslinux.py 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: psutil/_pslinux.py differs from the pinned commit"
fi

# The upfront sha check catches tampering with the overlaid regression test;
# the copy afterwards restores it regardless, so deleting/skipping/editing
# the failing test can never let it vanish from the run.
cur=$(sha256sum "$SRC/tests/test_linux.py" 2>/dev/null | cut -d' ' -f1)
if [ "$cur" = "$GOLDEN_SHA" ]; then
  echo "ok: tests/test_linux.py is byte-identical to the upstream regression test"
else
  fail "tests/test_linux.py was altered (${cur:-missing})"
fi
cp "$GOLDEN" "$SRC/tests/test_linux.py"
after=$(sha256sum "$SRC/tests/test_linux.py" | cut -d' ' -f1)
if [ "$after" = "$GOLDEN_SHA" ]; then
  echo "ok: regression test restored byte-identically from /opt/golden"
else
  fail "could not restore the upstream regression test"
fi

porcelain=$(git -C "$SRC" status --porcelain --untracked-files=no 2>/dev/null || true)
expected=" M psutil/_pslinux.py"$'\n'" M tests/test_linux.py"
if [ "$porcelain" = "$expected" ]; then
  echo "ok: tracked working tree differs from the pinned commit only in the fix and the overlaid regression test"
else
  fail "unexpected tracked working-tree changes:"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

echo "== installed package resolution =="
resolved=$(cd "$RUNDIR" && python3 - <<'PY'
import psutil, psutil._pslinux
print(psutil.__file__ + "|" + psutil._pslinux.__file__)
PY
)
case "$resolved" in
  /app/src/psutil/*) echo "ok: import psutil resolves into /app/src: $resolved" ;;
  *) fail "import psutil did not resolve into /app/src: $resolved" ;;
esac

squat=$(
  find "$SRC" -maxdepth 1 \( -name 'sitecustomize.py' -o -name 'usercustomize.py' -o -name 'conftest.py' \) -print 2>/dev/null
)
if [ -n "$squat" ]; then
  fail "an interpreter-squatting helper was planted in the repository root:"
  printf '%s\n' "$squat" | sed 's/^/    /' >&2
else
  echo "ok: no sitecustomize/usercustomize/conftest squatting helpers at the repo root"
fi

# ---------- 1. the agent's own reproduction, both directions -----------------
echo "== reproduction against a pristine PRE-FIX tree (must crash with ValueError) =="
pristine_file=$(cd "$RUNDIR" && PYTHONPATH=/opt/pristine python3 -c 'import psutil; print(psutil.__file__)' 2>&1)
case "$pristine_file" in
  /opt/pristine/*) echo "ok: psutil resolves to the pristine pre-fix tree: $pristine_file" ;;
  *) fail "psutil did not resolve to the pristine tree from /opt/pristine: $pristine_file" ;;
esac

out=$(cd "$RUNDIR" && PYTHONPATH=/opt/pristine python3 "$REPRO" 2>&1)
rc=$?
printf '%s\n' "$out" | sed 's/^/    /'
if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q "ValueError: invalid literal for int() with base 10: b'kB'"; then
  echo "ok: reproduction crashes on a pre-fix tree (exit $rc) with the genuine ValueError"
else
  fail "reproduction did not crash with the genuine ValueError on a pre-fix tree (exit $rc)"
fi

echo "== reproduction against the repaired tree (must succeed with figures) =="
out=$(cd "$RUNDIR" && env -u PYTHONPATH python3 "$REPRO" 2>&1)
rc=$?
printf '%s\n' "$out" | sed 's/^/    /'
line=$(printf '%s\n' "$out" | grep -E '^swap total=[0-9]+ free=[0-9]+ used=[0-9]+ percent=' | tail -1)
if [ "$rc" -eq 0 ] && [ -n "$line" ]; then
  t=$(printf '%s' "$line" | sed -E 's/^swap total=([0-9]+) .*/\1/')
  f=$(printf '%s' "$line" | sed -E 's/^swap total=[0-9]+ free=([0-9]+) .*/\1/')
  u=$(printf '%s' "$line" | sed -E 's/^swap total=[0-9]+ free=[0-9]+ used=([0-9]+) .*/\1/')
  p=$(printf '%s' "$line" | sed -E 's/^.*percent=(.*)$/\1/')
  okfig=0
  if [ -n "$t" ] && [ -n "$f" ] && [ -n "$u" ] && [ -n "$p" ]; then
    if [ "$t" -gt 0 ] 2>/dev/null && [ "$u" -eq $((t - f)) ] 2>/dev/null; then
      if awk -v p="$p" 'BEGIN { exit !(p >= 0 && p <= 100) }'; then
        okfig=1
      fi
    fi
  fi
  if [ "$okfig" = 1 ]; then
    echo "ok: reproduction succeeds on the repaired tree: $line"
  else
    fail "reproduction figures are not consistent: $line"
  fi
else
  fail "reproduction failed on the repaired tree (exit $rc)"
fi

# ---------- 2. golden test + the project's own suite -------------------------
echo "== the project's own suite on the repaired tree =="
(
  cd "$SRC" || exit 1
  python -m pytest tests/test_linux.py \
    -k "TestSwapMemory or (TestVirtualMemoryAgainstFree and test_total)" \
    -p no:cacheprovider > /tmp/testsuite.log 2>&1
)
rc=$?
summary=$(grep -E "[0-9]+ passed" /tmp/testsuite.log | tail -1)
echo "pytest exit: $rc"
printf '%s\n' "$summary" | sed 's/^/    /'
if [ "$rc" -eq 0 ] && printf '%s\n' "$summary" | grep -qE "[0-9]+ passed" \
   && ! printf '%s\n' "$summary" | grep -qE "failed|error"; then
  echo "ok: the project's own suite is green: $summary"
else
  fail "the project's own suite is not green"
  tail -20 /tmp/testsuite.log | sed 's/^/    /' >&2 || true
fi

if grep -F "test_no_space_after_colon" /tmp/testsuite.log 2>/dev/null | grep -q "PASSED"; then
  echo "ok: the upstream regression test for this bug is in the run and passes"
else
  fail "the upstream regression test (test_no_space_after_colon) did not pass"
fi

# ---------- 3. hidden cases --------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  d=$(basename "$case")
  case "$d" in
    case-*) : ;;
    *) continue ;;
  esac
  n_hidden=$((n_hidden + 1))
  if ( cd "$RUNDIR" && env -u PYTHONPATH python3 "$case/driver.py" > "/tmp/hidden-$d.log" 2>&1 ); then
    echo "ok: hidden case $d: $(tail -1 "/tmp/hidden-$d.log")"
  else
    fail "hidden case $d"
    tail -10 "/tmp/hidden-$d.log" | sed 's/^/    /' >&2
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0