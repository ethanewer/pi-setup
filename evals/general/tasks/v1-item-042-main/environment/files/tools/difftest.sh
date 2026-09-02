#!/bin/bash
# Differential test harness: compare /app/vm.js against the reference
# tools/ref.py on every sample program, in all three modes.
# Usage: bash tools/difftest.sh
set -uo pipefail

fails=0
for elf in /app/samples/*.elf; do
  base=$(basename "$elf" .elf)
  echo "== $base =="
  python3 /app/tools/ref.py "$elf" --trace > /tmp/ref.trace; r1=$?
  node /app/vm.js "$elf" --trace > /tmp/ag.trace; r2=$?
  if [ "$r1" != "$r2" ] || ! diff -q /tmp/ref.trace /tmp/ag.trace >/dev/null; then
    echo "TRACE MISMATCH (status $r1 vs $r2)"
    diff /tmp/ref.trace /tmp/ag.trace | head -20
    fails=1
  else
    echo "  trace ok"
  fi
  python3 /app/tools/ref.py "$elf" --snapshot > /tmp/ref.snap
  node /app/vm.js "$elf" --snapshot > /tmp/ag.snap
  if ! diff -q /tmp/ref.snap /tmp/ag.snap >/dev/null; then
    echo "SNAPSHOT MISMATCH"
    diff /tmp/ref.snap /tmp/ag.snap | head -4
    fails=1
  else
    echo "  snapshot ok"
  fi
  python3 /app/tools/ref.py "$elf" > /tmp/ref.out; r1=$?
  node /app/vm.js "$elf" > /tmp/ag.out; r2=$?
  if [ "$r1" != "$r2" ] || ! cmp -s /tmp/ref.out /tmp/ag.out; then
    echo "PLAIN MISMATCH (status $r1 vs $r2)"
    fails=1
  else
    echo "  plain ok"
  fi
done

if [ "$fails" = "0" ]; then
  echo "difftest: ALL SAMPLES MATCH"
else
  echo "difftest: FAILURES PRESENT"
fi
exit "$fails"