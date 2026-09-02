#!/bin/bash
# Verifier for hollow-keystone. Runs as root after the agent finishes.
# Writes numeric reward to /logs/verifier/reward.txt.
set -u

fails=0
pass(){ echo "PASS: $1"; }
fail(){ echo "FAIL: $1"; fails=$((fails+1)); }

BASEDIR=/opt/frozen
DEVZONE=/app/devzone

# ---- 1. Hygiene: only /app/src/fixed.c may differ among source files ----
for f in src/tokens.c src/tokens.h src/Makefile sample.conf; do
  if cmp -s "/app/$f" "$BASEDIR/$f"; then pass "protected file unchanged: $f"; else fail "protected file modified: $f"; fi
done

# No unexpected extra source/config files in /app/src (allow kvcat artifact).
for x in /app/src/*; do
  b=$(basename "$x")
  case "$b" in
    tokens.c|tokens.h|Makefile|fixed.c|kvcat) ;;
    *) fail "unexpected extra file in /app/src: $b" ;;
  esac
done
pass "no unexpected extra source files in /app/src"

# The sanctioned file must have actually been repaired in source (differ from the
# buggy shipped copy). The behavioral + valgrind checks below are authoritative for
# correctness (no short-circuit, no exit-without-cleanup, no definite leaks).
if cmp -s /app/src/fixed.c "$BASEDIR/src/fixed.c"; then
  fail "fixed.c not actually modified (still the buggy shipped copy)"
else
  pass "fixed.c edited in source"
fi

# ---- 2. Build the deliverable source and verify behavior + no leaks -------
make -C /app/src clean >/dev/null 2>&1 || true
if ! make -C /app/src >/dev/null 2>&1; then
  fail "rebuild of /app/src/fixed.c failed"
  echo "0" > /logs/verifier/reward.txt
  echo "REWARD=0 rebuild-failed"
  exit 0
fi
pass "kvcat builds cleanly from delivered fixed.c"

VG="valgrind --quiet --error-exitcode=42 --leak-check=full --errors-for-leak-kinds=definite,possible"

run_case() {
  local name=$1 file=$2 exp=$3
  local log; log=$(mktemp)
  local out
  out=$($VG /app/src/kvcat "$file" 2>"$log")
  local rc=$?
  rm -f "$log"
  if [ "$rc" -ne 0 ]; then fail "case $name: rc=$rc (definite/possible leaks detected)"; return; fi
  if [ "$out" != "$exp" ]; then
    fail "case $name: output mismatch"
    echo "--- got ---"; printf '%s\n' "$out"
    echo "--- want ---"; printf '%s\n' "$exp"
    return
  fi
  pass "case $name: correct output and no definite leaks"
}

EXP_VISIBLE=$'sum:alpha=15\nsum:beta=4\nsum:gamma=7\nerrors:0'
run_case visible /app/sample.conf "$EXP_VISIBLE"

EXP_C0=$'sum:alpha=4\nsum:beta=2\nerrors:2'
run_case hidden0 /tests/hidden/case0.conf "$EXP_C0"

EXP_C1=$'sum:omega=3\nsum:zeta=7\nerrors:2'
run_case hidden1 /tests/hidden/case1.conf "$EXP_C1"

EXP_C2=$'sum:BAR=10\nsum:bar=4\nerrors:4'
run_case hidden2 /tests/hidden/case2.conf "$EXP_C2"

EXP_C3=$'errors:4'
run_case hidden3 /tests/hidden/case3.conf "$EXP_C3"

# ---- 3. Merge deliverables ----
EXP_CONFIG=$'[profile]\nbuffer = 1024\nmode = "turbofan"\nstream = true'
EXP_DEPS=$'cache=2.9.0\nmonitor=9.7.2\nserver=4.2.1'

if [ -f /app/merged.diff ]; then
  if grep -qE '<<<<<<<|>>>>>>>' /app/merged.diff; then fail "merged.diff contains conflict markers"; else pass "merged.diff present and conflict-free"; fi
else
  fail "missing /app/merged.diff"
fi

if [ -f /app/deps.lock ]; then
  if [ "$(cat /app/deps.lock)" = "$EXP_DEPS" ]; then pass "deps.lock matches resolved dependency set"; else fail "deps.lock mismatch"; fi
else
  fail "missing /app/deps.lock"
fi

# devzone: no unmerged paths, no conflict markers, resolved content correct.
if [ -d "$DEVZONE/.git" ]; then
  if git -C "$DEVZONE" status --porcelain 2>/dev/null | grep -qE '^(U|AA|DD|AU|UA|DU|UD)'; then
    fail "devzone still has unmerged paths"
  else
    pass "devzone has no unmerged paths"
  fi
  if grep -qE '<<<<<<<|>>>>>>>' "$DEVZONE/config.toml" "$DEVZONE/deps.txt" 2>/dev/null; then
    fail "conflict markers in devzone working files"
  else
    pass "no conflict markers in devzone working files"
  fi
  if [ "$(cat "$DEVZONE/config.toml")" = "$EXP_CONFIG" ]; then pass "devzone config.toml resolved correctly"; else fail "devzone config.toml mismatch"; fi
  if [ "$(cat "$DEVZONE/deps.txt")" = "$EXP_DEPS" ]; then pass "devzone deps.txt resolved correctly"; else fail "devzone deps.txt mismatch"; fi
else
  fail "devzone git repository missing"
fi

# merged.diff must reconstruct base -> merged content.
if [ -f /app/merged.diff ] && [ -f "$BASEDIR/base/config.toml" ]; then
  RECON_OK=0
  for P in 1 0; do
    RAFT=$(mktemp -d)
    cp "$BASEDIR"/base/* "$RAFT"/ 2>/dev/null
    ( cd "$RAFT" && patch -p$P -i /app/merged.diff >/dev/null 2>&1 )
    if [ -f "$RAFT/config.toml" ] && [ "$(cat "$RAFT/config.toml")" = "$EXP_CONFIG" ] \
       && [ -f "$RAFT/deps.txt" ] && [ "$(cat "$RAFT/deps.txt")" = "$EXP_DEPS" ]; then
      pass "merged.diff reconstructs base content (patch -p$P)"
      RECON_OK=1
      rm -rf "$RAFT"
      break
    fi
    rm -rf "$RAFT"
  done
  if [ "$RECON_OK" -eq 0 ]; then
    fail "merged.diff does not reconstruct base content"
    echo "--- merged.diff head ---"; head -20 /app/merged.diff
  fi
fi

# ---- Reward ----
if [ "$fails" -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward fails=$fails"
exit 0
