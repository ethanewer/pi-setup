#!/bin/bash
# Verifier for harbor-notch. Runs as root after the agent finishes.
# Recompiles /app/src/mtally from the delivered /app/src/mtally.c, enforces
# the hygiene rules (protected files byte-identical, no extra files, no
# suppression files), and EXECUTES the deliverable under Valgrind
# (--leak-check=full, leak errors fatal) on the visible sample and every
# hidden case in /tests/hidden. Writes 0/1 to /logs/verifier/reward.txt.
set -u

fails=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; fails=$((fails+1)); }

BASEDIR=/opt/frozen
VG="valgrind --quiet --error-exitcode=42 --leak-check=full --errors-for-leak-kinds=definite,possible"

# ---- 1. Hygiene: only /app/src/mtally.c may differ among shipped files ----
for f in src/store.c src/store.h src/Makefile data/sample.tly; do
  if cmp -s "/app/$f" "$BASEDIR/$f"; then pass "protected file unchanged: $f"; else fail "protected file modified: $f"; fi
done

for x in /app/src/*; do
  b=$(basename "$x")
  case "$b" in
    mtally.c|store.c|store.h|Makefile|mtally) ;;
    *) fail "unexpected extra file in /app/src: $b" ;;
  esac
done
pass "no unexpected extra source files in /app/src"

if find /app -name '*.sup' -o -name '*suppression*' 2>/dev/null | grep -q .; then
  fail "suppression file present under /app"
else
  pass "no suppression files under /app"
fi

# The sanctioned file must have actually been repaired in source (the
# behavioral + valgrind checks below remain authoritative: any exit-hack or
# leak fails them).
if cmp -s /app/src/mtally.c "$BASEDIR/src/mtally.c"; then
  fail "mtally.c not actually modified (still the buggy shipped copy)"
else
  pass "mtally.c edited in source"
fi

# ---- 2. Build the deliverable --------------------------------------------
make -C /app/src clean >/dev/null 2>&1 || true
if ! make -C /app/src > /tmp/mtally_build.log 2>&1; then
  fail "rebuild of /app/src/mtally from delivered mtally.c failed"
  cat /tmp/mtally_build.log >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi
pass "mtally builds cleanly from delivered mtally.c"

# ---- 3. Visible case: sample.tly must tally, exit 0, and leak nothing ----
log=$(mktemp)
out=$($VG /app/src/mtally /app/data/sample.tly 2>"$log")
rc=$?
rm -f "$log"
if [ "$rc" -ne 0 ]; then
  fail "visible case: rc=$rc (nonzero status or definite/possible leaks detected)"
elif [ "$out" != "$(printf 'tally:alpha=7\ntally:beta=10\nbad:1')" ]; then
  fail "visible case: output mismatch"
  echo "--- got ---"; printf '%s\n' "$out"
  echo "--- want ---"; printf 'tally:alpha=7\ntally:beta=10\nbad:1\n'
else
  pass "visible case: correct output, exit 0, no leaks"
fi

# ---- 4. Hidden cases ------------------------------------------------------
hidden_dir=/tests/hidden
if [ ! -d "$hidden_dir" ]; then
  fail "hidden dir missing"
else
  for d in "$hidden_dir"/*/; do
    name=$(basename "$d")
    mode=$(cat "$d/mode" 2>/dev/null | tr -d '[:space:]')
    wantrc=$(cat "$d/rc" 2>/dev/null | tr -d '[:space:]')
    exp=$(cat "$d/expected.txt" 2>/dev/null)
    if [ -z "$mode" ] || [ -z "$wantrc" ]; then
      fail "hidden '$name': malformed case metadata"
      continue
    fi
    if [ "$mode" = "file" ]; then
      tgt="$d/input.tly"
      [ -f "$tgt" ] || { fail "hidden '$name': missing input.tly"; continue; }
    else
      tgt="/nonexistent/mtally-$name.tly"
    fi
    log=$(mktemp)
    out=$($VG /app/src/mtally "$tgt" 2>"$log")
    rc=$?
    rm -f "$log"
    if [ "$rc" -ne "$wantrc" ]; then
      fail "hidden '$name': rc=$rc want=$wantrc (42 = definite/possible leaks detected)"
      continue
    fi
    if [ "$out" != "$exp" ]; then
      fail "hidden '$name': output mismatch"
      echo "--- got ---"; printf '%s\n' "$out"
      echo "--- want ---"; printf '%s\n' "$exp"
      continue
    fi
    pass "hidden '$name': correct output, exit $rc, no leaks"
  done
fi

if [ "$fails" -eq 0 ]; then
  echo "1" > /logs/verifier/reward.txt
else
  echo "0" > /logs/verifier/reward.txt
fi
exit 0
