#!/bin/bash
# flint-anchor verifier: executes every deliverable on the visible fixtures
# and on the hidden/ generalization inputs under /tests/hidden.
#   deliverable   competency                                     check
#   /app/callsites.py          define call sites (top-3 frames)  output compares to independent reference on hidden traces
#   /app/vm/sweep.c            diagnose GC sweep bug             compiled with the sweep driver; randomized+adversarial heaps
#   /app/math/Sum.hpp          C++11 constexpr port              -std=c++11 -pedantic-errors compile with static_asserts
#   /app/mkbin.py + /app/bin/flint_app   regenerate/run exe from IR  builds hidden IR+lib executables, runs them
#   /app/sections.py           sections & symbol-string tables   expected output computed by elf_check.py for each ELF
# Always ends by writing /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
PASS=1
fail() { echo "FAIL: $1"; PASS=0; }

for need in \
  /app/callsites.py /app/vm/sweep.c /app/math/Sum.hpp \
  /app/mkbin.py /app/sections.py /app/bin/flint_app; do
  [ -e "$need" ] || fail "missing deliverable $need"
done
[ -e /app/vm/sweep.h ] || fail "missing fixture /app/vm/sweep.h"
[ -e /app/math/Sum.hpp ] || fail "missing header /app/math/Sum.hpp"

# --------------------------------------------------------------------------
# Module A: call-site grouper. Recompute expected with an independent
# reference implementing the documented top-3-innermost-frame rule.
# --------------------------------------------------------------------------
check_callsites() {
  local in="$1" out
  out=$(python3 /app/callsites.py "$in") || { fail "(A) grouper crashed on $in"; return; }
  local exp
  exp=$(python3 - "$in" <<'PY'
import sys, collections
path = sys.argv[1]
counts = collections.Counter()
for line in open(path):
    line = line.strip()
    if not line: continue
    fr = [t for t in line.split(";") if t != ""]
    counts[";".join(fr[:3])] += 1
exp = "\n".join("%d %s" % (c, k) for k, c in
      sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:10])
print(exp)
PY
  )
  [ "$out" = "$exp" ] || fail "(A) callsites mismatch on $in"
}

check_callsites /app/samples/traces.txt
for f in /tests/hidden/callsites/*.txt; do
  check_callsites "$f"
done

# --------------------------------------------------------------------------
# Module B: GC sweeping path. Compile the agent's sweep.c with the driver and
# require every randomized/adversarial heap to match the brute-force
# reference and the RLE invariants.
# --------------------------------------------------------------------------
if ! gcc -I/app/vm -o /tmp/sweep_driver /tests/sweep_driver.c /app/vm/sweep.c 2>/tmp/sweep_build.log; then
  fail "(B) sweep.c failed to compile: $(tail -3 /tmp/sweep_build.log | tr '\n' ' ')"
else
  /tmp/sweep_driver > /tmp/sweep_driver.out 2>/tmp/sweep_driver.err || \
    fail "(B) sweep driver reported mismatches: $(head -3 /tmp/sweep_driver.err | tr '\n' ' ')"
fi

# --------------------------------------------------------------------------
# Module C: C++11 constexpr port. Must compile cleanly under strict C++11 and
# yield the right constant sums on every static_assert.
# --------------------------------------------------------------------------
if ! g++ -std=c++11 -Wall -Wextra -pedantic-errors -Werror \
     -o /tmp/sum_check /tests/sum_check.cpp 2>/tmp/sum_build.log; then
  fail "(C) Sum.hpp not clean under -std=c++11: $(tail -4 /tmp/sum_build.log | tr '\n' ' ')"
else
  /tmp/sum_check > /dev/null || fail "(C) sum_check run failed"
fi

# --------------------------------------------------------------------------
# Module D: deliverable executable built from the emitted IR.
# Visible binary must run and answer the documented value.
# --------------------------------------------------------------------------
vis=$(/app/bin/flint_app 2>/dev/null || true)
[ "$vis" = "46" ] || fail "(D) visible IR executable output wrong: '$vis'"

for i in 1 2 3; do
  gcc -shared -fPIC -o /tmp/libcore_$i.so /tests/hidden/ir/case$i/lib.c 2>/tmp/lib_build.log || {
    fail "(D) hidden lib$i build failed"; continue; }
  if ! python3 /app/mkbin.py /tests/hidden/ir/case$i/ir.s /tmp/libcore_$i.so /tmp/app_$i 2>/tmp/mk.log; then
    fail "(D) mkbin.py failed on case$i: $(tail -2 /tmp/mk.log | tr '\n' ' ')"
    continue
  fi
  [ -x /tmp/app_$i ] || { fail "(D) case$i produced no executable"; continue; }
  got=$(/tmp/app_$i || true)
  want=$(cat /tests/hidden/ir/case$i/expected.txt)
  [ "$got" = "$want" ] || fail "(D) hidden case$i wrong output: got '$got' want '$want'"
done

# --------------------------------------------------------------------------
# Module E: sections & symbol-string resolver. For each ELF, run the
# deliverable and compare line-for-line to the independent expected output.
# --------------------------------------------------------------------------
check_sections() {
  local elf="$1"
  python3 /app/sections.py "$elf" > /tmp/sec.out 2>/dev/null || { fail "(E) sections.py crashed on $elf"; return; }
  python3 /tests/elf_check.py "$elf" /tmp/sec.out > /tmp/sec_check.out 2>&1 || fail "(E) sections mismatch on $elf"
}

check_sections /app/bin/flint_app
check_sections /tmp/app_1     # built from hidden IR/lib case 1
check_sections /tmp/app_3     # built from hidden IR/lib case 3 (negative constant)

# extra ELF sample (plain C program built at verify time)
gcc -no-pie -o /tmp/plain_prog /tests/hidden/elf/plain_prog.c 2>/dev/null || \
  fail "(E) could not build extra ELF sample"
check_sections /tmp/plain_prog

# --------------------------------------------------------------------------
[ "$PASS" = 1 ] && reward=1 || reward=0
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"
