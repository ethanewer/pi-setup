#!/usr/bin/env bash
#
# hollow-dial verifier. Runs as root after the agent finishes; /tests is mounted
# read-only. Re-executes every deliverable from first principles and writes the
# numeric reward to /logs/verifier/reward.txt.
set -uo pipefail
mkdir -p /logs/verifier
R=/logs/verifier/reward.txt
fail=0
report(){ if [ "$1" = "1" ]; then echo "PASS: $2"; else echo "FAIL: $2"; fail=$((fail + 1)); fi; }
V=/tmp/vrfy; rm -rf "$V"; mkdir -p "$V"

py=/usr/bin/python3
[ -x "$py" ] || py=python3

# ---------------------------------------------------------------------------
# 0. All deliverables present (and arch_report/self_host not empty).
# ---------------------------------------------------------------------------
ok=1
for f in /app/classify.py /app/arch_report.json /app/mips_interp.c /app/mips_out.txt \
         /app/eval.py /app/self_host.txt; do
  [ -s "$f" ] || { ok=0; echo "missing or empty $f"; }
done
report $ok "all six deliverables present and non-empty"

# ---------------------------------------------------------------------------
# 1. classify.py - architecture classification from headers (executes deliverable)
# ---------------------------------------------------------------------------
run_cls(){ "$py" /app/classify.py "$1" 2>/dev/null; }

ok=1
json=$(run_cls /app/samples/sum.pdp11)
arch=$(printf '%s' "$json" | $py -c 'import json,sys;print(json.load(sys.stdin)["arch"])')
host=$(printf '%s' "$json" | $py -c 'import json,sys;print(json.load(sys.stdin)["host_executable"])')
[ "$arch" = "pdp11" ] || { ok=0; echo "sample arch=$arch"; }
[ "$host" = "False" ] || { ok=0; echo "sample host flag=$host"; }
rarch=$(cat /app/arch_report.json | $py -c 'import json,sys;print(json.load(sys.stdin)["arch"])')
[ "$rarch" = "pdp11" ] || { ok=0; echo "arch_report.json arch=$rarch"; }
report $ok "classify.py recognizes the provided PDP-11 a.out and arch_report.json agrees"

# hidden arch cases (differing architectures + malformed/edge)
hok=1
check(){ # <file> <expected_arch> [expected_host_flag]
  local f="$1" e="$2"; local fl="${3:-_}"
  local j a h
  j=$(run_cls "$f")
  a=$(printf '%s' "$j" | $py -c 'import json,sys;print(json.load(sys.stdin)["arch"])')
  h=$(printf '%s' "$j" | $py -c 'import json,sys;print(json.load(sys.stdin)["host_executable"])')
  if [ "$a" != "$e" ]; then echo "  arch($(basename "$f"))=$a expected=$e"; hok=0; fi
  if [ -n "$fl" ] && [ "$fl" = "T" ] && [ "$h" != "True" ]; then
    echo "  host_executable($(basename "$f"))=$h expected True"; hok=0; fi
  if [ -n "$fl" ] && [ "$fl" = "F" ] && [ "$h" != "False" ]; then
    echo "  host_executable($(basename "$f"))=$h expected False"; hok=0; fi
}
check /tests/hidden/arch/pdp11_alt.bin pdp11 F
check /tests/hidden/arch/x86_64_elf.bin x86_64 T
check /tests/hidden/arch/mips_elf.bin mips F
j=$(run_cls /tests/hidden/arch/truncated_elf.bin)
fmt=$(printf '%s' "$j" | $py -c 'import json,sys;print(json.load(sys.stdin)["format"])')
[ "$fmt" = "elf-truncated" ] || { echo "  truncated_elf format=$fmt"; hok=0; }
j=$(run_cls /tests/hidden/arch/notes.txt)
arch=$(printf '%s' "$j" | $py -c 'import json,sys;print(json.load(sys.stdin)["arch"])')
[ "$arch" = "unknown" ] || { echo "  notes.txt arch=$arch"; hok=0; }
report $hok "classify.py generalizes to hidden architectures and degrades gracefully on truncated/text inputs"

# ---------------------------------------------------------------------------
# 2. MIPS interpreter - recompile the deliverable source fresh, run hidden ELFs
# ---------------------------------------------------------------------------
ok=1
if ! gcc -O2 -o "$V/mi" /app/mips_interp.c 2>"$V/cc.err"; then
  ok=0; echo "  recompile of /app/mips_interp.c failed: $(head -c 300 "$V/cc.err")"
else
  # visible: sample output must equal mips_out.txt
  if ! "$V/mi" /app/samples/greet.mips > "$V/g.out" 2>/dev/null \
     || ! cmp -s "$V/g.out" /app/mips_out.txt; then
    ok=0; echo "  greet.mips did not reproduce /app/mips_out.txt"
  fi
  # hidden programs must match their expected stdout byte-for-byte
  for n in prog1 prog2 prog3 prog4; do
    if ! "$V/mi" "/tests/hidden/mips/$n.mips" > "$V/h.out" 2>/dev/null \
       || ! cmp -s "$V/h.out" "/tests/hidden/mips/$n.out"; then
      ok=0; echo "  hidden MIPS program $n did not match expected output"
    fi
  done
  # malformed: an ELF with an unsupported opcode must be rejected
  "$V/mi" /tests/hidden/mips/bad_inst.mips >/dev/null 2>"$V/b.err"
  brc=$?
  if [ "$brc" -eq 0 ] || [ ! -s "$V/b.err" ]; then
    ok=0; echo "  bad_inst.mips rc=$brc (expected nonzero + stderr) stderr=$(head -c 120 "$V/b.err")"
  fi
fi
report $ok "recompiled MIPS interpreter runs the sample + all hidden ELF programs and rejects an unsupported instruction"

# ---------------------------------------------------------------------------
# 3. eval.py - Liz evaluator, direct == one-level self-interpretation
# ---------------------------------------------------------------------------
ok=1
"$py" /app/eval.py /app/samples/hello.lsp > "$V/hello.out" 2>&1 || ok=0
printf '42\n14\n77\n' > "$V/hello.exp"
cmp -s "$V/hello.out" "$V/hello.exp" || { ok=0; echo "  hello.lsp mismatch"; }
# visible self-interpretation proof: fib (direct) == self (hosted) == self_host.txt
"$py" /app/eval.py /app/samples/fib.lsp > "$V/fib.out" 2>&1 || ok=0
"$py" /app/eval.py /app/samples/self.lsp > "$V/self.out" 2>&1 || ok=0
cmp -s "$V/fib.out" "$V/self.out" || { ok=0; echo "  fib != self (direct vs self-interpreted)"; }
cmp -s "$V/self.out" /app/self_host.txt || { ok=0; echo "  self != self_host.txt"; }
report $ok "Liz evaluator runs directly and via one self-interpreter level with identical output (self_host.txt)"

hok=1
for c in case_list case_fib case_quote; do
  "$py" /app/eval.py "/tests/hidden/eval/$c/prog.lsp" > "$V/d.out" 2>"$V/d.err" || hok=0
  "$py" /app/eval.py "/tests/hidden/eval/$c/hosted.lsp" > "$V/hi.out" 2>"$V/hi.err" || hok=0
  cmp -s "$V/d.out" "/tests/hidden/eval/$c/expected.txt" || { echo "  $c direct != expected"; hok=0; }
  cmp -s "$V/hi.out" "/tests/hidden/eval/$c/expected.txt" || { echo "  $c hosted != expected"; hok=0; }
  cmp -s "$V/d.out" "$V/hi.out" || { echo "  $c direct != hosted"; hok=0; }
done
# malformed Liz program (division by zero) must be rejected
"$py" /app/eval.py /tests/hidden/eval/case_div0/prog.lsp > "$V/d0.out" 2>"$V/d0.err"
drc=$?
if [ "$drc" -eq 0 ] || ! grep -q "division by zero" "$V/d0.err"; then
  hok=0; echo "  div0 rc=$drc stderr=$(head -c 120 "$V/d0.err")"
fi
report $hok "Liz generalizes on hidden targets (direct==self-interpreted==expected) and rejects a malformed program"

if [ "$fail" = "0" ]; then echo 1 > "$R"; else echo 0 > "$R"; fi
echo "VERIFIER_COMPLETE failures=$fail reward=$(cat "$R")"