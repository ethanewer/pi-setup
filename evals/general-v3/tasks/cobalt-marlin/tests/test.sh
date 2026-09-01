#!/bin/bash
# Verifier for cobalt-marlin. Runs as root after the agent finishes.
# Rebuilds /app/src/batchstat from the delivered /app/src/batchstat.c and runs
# it under Valgrind on the visible sample and every hidden input, comparing
# stdout, exit code, report file, and requiring zero in-use blocks at exit
# (the atexit-registered lifecycle really ran). Writes the numeric reward to
# /logs/verifier/reward.txt.
set -u

fails=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

BASEDIR=/opt/frozen

# ---- 1. Hygiene: only /app/src/batchstat.c may differ among seeded files ----
for f in src/tags.c src/tags.h src/Makefile sample_input.txt; do
  if cmp -s "/app/$f" "$BASEDIR/$f"; then pass "protected file unchanged: $f"; else fail "protected file modified: $f"; fi
done

for x in /app/src/*; do
  b=$(basename "$x")
  case "$b" in
    tags.c|tags.h|Makefile|batchstat.c|batchstat) ;;
    *) fail "unexpected extra file in /app/src: $b" ;;
  esac
done
pass "no unexpected extra source files in /app/src"

# The sanctioned file must have actually been repaired in source.
if cmp -s /app/src/batchstat.c "$BASEDIR/src/batchstat.c"; then
  fail "batchstat.c not actually modified (still the buggy shipped copy)"
else
  pass "batchstat.c edited in source"
fi

# Source hygiene: no short-circuit termination, no suppression mechanisms,
# and the registered atexit lifecycle must still be in place.
if grep -nE '\b_exit\b|\b_Exit\b|\bquick_exit\b|\babort[[:space:]]*\(|\bVALGRIND_' /app/src/batchstat.c >/dev/null 2>&1; then
  fail "forbidden short-circuit/suppression token present in batchstat.c"
else
  pass "no short-circuit/suppression tokens in batchstat.c"
fi
if grep -q 'atexit' /app/src/batchstat.c; then
  pass "atexit-registered lifecycle intact"
else
  fail "atexit-registered lifecycle removed"
fi

# ---- 2. Rebuild and verify behavior + clean teardown under Valgrind ---------
make -C /app/src clean >/dev/null 2>&1 || true
if ! make -C /app/src >/dev/null 2>&1; then
  fail "rebuild of /app/src/batchstat.c failed"
  echo "0" > /logs/verifier/reward.txt
  echo "REWARD=0 rebuild-failed"
  exit 0
fi
pass "batchstat builds cleanly from delivered batchstat.c"

VG="valgrind --leak-check=full --show-leak-kinds=all --errors-for-leak-kinds=all --error-exitcode=42"

run_case() {
  local name=$1 input=$2 exp_rc=$3 exp_out=$4 exp_audit=$5
  local rep vglog out rc
  rep=$(mktemp)
  vglog=$(mktemp)
  out=$($VG /app/src/batchstat "$input" "$rep" 2>"$vglog")
  rc=$?
  if [ "$rc" -eq 42 ]; then
    fail "case $name: leak checker flagged errors (rc=42)"
    rm -f "$rep" "$vglog"
    return
  fi
  if ! grep -q "in use at exit: 0 bytes in 0 blocks" "$vglog"; then
    fail "case $name: heap still in use at exit (registered cleanup did not run)"
    rm -f "$rep" "$vglog"
    return
  fi
  if [ "$rc" -ne "$exp_rc" ]; then
    fail "case $name: rc=$rc, want $exp_rc"
    rm -f "$rep" "$vglog"
    return
  fi
  if [ "$out" != "$exp_out" ]; then
    fail "case $name: stdout mismatch"
    echo "--- got ---"; printf '%s\n' "$out"
    echo "--- want ---"; printf '%s\n' "$exp_out"
    rm -f "$rep" "$vglog"
    return
  fi
  if [ "$(cat "$rep")" != "audit:tags=$exp_audit" ]; then
    fail "case $name: report file mismatch (got '$(cat "$rep")', want 'audit:tags=$exp_audit')"
    rm -f "$rep" "$vglog"
    return
  fi
  rm -f "$rep" "$vglog"
  pass "case $name: correct output, exit code, audit line, zero in-use blocks at exit"
}

run_case visible /app/sample_input.txt 0 $'sum:alpha=15\nsum:beta=-5\nsum:total=12\nerrors:3' 3
run_case hidden0 /tests/hidden/case0.txt 0 $'sum:errors_per_sec=-4\nsum:latency=5\nsum:requests=73\nsum:uptime=999999\nerrors:2' 4
run_case hidden1 /tests/hidden/case1.txt 2 $'aborted:too-many-errors' 2
run_case hidden2 /tests/hidden/case2.txt 2 $'aborted:too-many-errors' 0
run_case hidden3 /tests/hidden/case3.txt 0 $'sum:delta=10\nerrors:8' 1
run_case hidden4 /tests/hidden/case4.txt 0 $'sum:echo=8\nerrors:3' 1

# ---- Reward -----------------------------------------------------------------
if [ "$fails" -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward fails=$fails"
exit 0
