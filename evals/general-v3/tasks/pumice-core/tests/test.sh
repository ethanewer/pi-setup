#!/bin/bash
# Verifier for pumice-core: re-executes /app/vm.js on the visible sample and on
# every hidden big-endian MIPS32 image in /tests/hidden/mips, comparing stdout
# byte-for-byte and exit statuses exactly. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. Never crashes on malformed/missing deliverables.
set -u
mkdir -p /logs/verifier
V=/tmp/vrfy_pumice
rm -rf "$V"; mkdir -p "$V"
fail=0
note(){ if [ "$1" = 1 ]; then echo "PASS: $2"; else echo "FAIL: $2"; fail=$((fail+1)); fi; }

# 0. deliverables present
ok=1
[ -s /app/vm.js ] || { ok=0; echo "missing /app/vm.js"; }
[ -s /app/sample_out.txt ] || { ok=0; echo "missing /app/sample_out.txt"; }
note $ok "both deliverables present and non-empty"

# 1. visible sample: fresh run must reproduce /app/sample_out.txt
ok=1
node /app/vm.js /app/samples/boot.elf > "$V/boot.out" 2>"$V/boot.err"
rc=$?
[ "$rc" = 0 ] || { ok=0; echo "boot.elf rc=$rc stderr=$(head -c 150 "$V/boot.err")"; }
cmp -s "$V/boot.out" /app/sample_out.txt || { ok=0; echo "fresh boot.elf run differs from /app/sample_out.txt"; }
note $ok "vm.js reproduces the visible sample output (sample_out.txt)"

# 2. hidden programs: exact stdout + exact exit status
hok=1
for n in prog_math prog_fib prog_delay prog_str; do
  node /app/vm.js "/tests/hidden/mips/$n.elf" > "$V/$n.out" 2>"$V/$n.err"
  rc=$?
  want_rc=$(cat "/tests/hidden/mips/$n.rc" 2>/dev/null || echo "?")
  if [ "$rc" != "$want_rc" ]; then hok=0; echo "  $n rc=$rc want=$want_rc"; fi
  if ! cmp -s "$V/$n.out" "/tests/hidden/mips/$n.out"; then
    hok=0; echo "  $n stdout differs (got $(head -c 80 "$V/$n.out" | tr '\n' ' '))"
  fi
done
note $hok "hidden arithmetic/recursion/delay-slot/string programs match stdout and exit status"

# 3. malformed-image behavior: unsupported opcode and out-of-range memory
hok=1
node /app/vm.js /tests/hidden/mips/prog_badinst.elf > "$V/bi.out" 2>"$V/bi.err"
rc=$?
[ "$rc" = 2 ] || { hok=0; echo "  badinst rc=$rc want=2"; }
[ -s "$V/bi.err" ] || { hok=0; echo "  badinst produced no stderr diagnostic"; }
node /app/vm.js /tests/hidden/mips/prog_memerr.elf > "$V/me.out" 2>"$V/me.err"
rc=$?
[ "$rc" = 7 ] || { hok=0; echo "  memerr rc=$rc want=7"; }
[ -s "$V/me.err" ] || { hok=0; echo "  memerr produced no stderr diagnostic"; }
note $hok "unsupported instruction exits 2 and out-of-range memory exits 7 with stderr diagnostics"

# 4. not-an-ELF input must fail gracefully (no crash/traceback)
junk="$V/junk.bin"; printf 'this is not an elf at all, just text padding....' > "$junk"
gok=1
node /app/vm.js "$junk" > "$V/junk.out" 2>"$V/junk.err"
rc=$?
[ "$rc" != 0 ] || { gok=0; echo "  junk input exited 0"; }
node /app/vm.js > "$V/noarg.out" 2>"$V/noarg.err"
rc=$?
[ "$rc" != 0 ] || { gok=0; echo "  missing-arg invocation exited 0"; }
note $gok "non-ELF and missing-argument inputs fail gracefully with nonzero status"

if [ "$fail" = 0 ]; then echo 1 > /logs/verifier/reward.txt; else echo 0 > /logs/verifier/reward.txt; fi
echo "VERIFIER_COMPLETE failures=$fail reward=$(cat /logs/verifier/reward.txt)"
exit 0
