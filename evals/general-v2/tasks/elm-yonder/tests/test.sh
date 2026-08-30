#!/usr/bin/env bash
# Verifier for elm-yonder (executes-deliverable).
# Runs the four /app programs on the visible + hidden fixtures and writes the
# numeric reward. Hidden inputs are mounted read-only at /tests/hidden.
set -u
mkdir -p /logs/verifier
R=/logs/verifier/reward.txt

fail() {
  echo "0" > "$R"
  exit 0
}

for f in link.py all.bc elf.py sym.py solver.py; do
  [ -f "/app/$f" ] || fail "missing deliverable: $f"
done

# ---- 1) /app/all.bc : coalesced, cross-module resolved, debug metadata ----
llvm-dis-18 /app/all.bc -o /tmp/all_dis.ll 2>/dev/null || fail "llvm-dis all.bc"
grep -qE 'define[^;]*@add_twice'  /tmp/all_dis.ll || fail "all.bc lacks add_twice"
grep -qE 'define[^;]*@add_one'    /tmp/all_dis.ll || fail "all.bc lacks add_one"
grep -qE 'define[^;]*@call_twice' /tmp/all_dis.ll || fail "all.bc lacks call_twice"
grep -qE 'define[^;]*@main'       /tmp/all_dis.ll || fail "all.bc lacks main"
grep -qE 'declare[^;]*@add_twice' /tmp/all_dis.ll && fail "all.bc has unresolved add_twice"
grep -q 'DICompileUnit'           /tmp/all_dis.ll || fail "all.bc lacks debug metadata"

# ---- 2) link.py on a hidden IR pair ----
python3 /app/link.py -o /tmp/h.bc /tests/hidden/ir/a.ll /tests/hidden/ir/b.ll \
  || fail "link.py failed on hidden IR"
llvm-dis-18 /tmp/h.bc -o /tmp/h_dis.ll 2>/dev/null || fail "llvm-dis hidden bc"
grep -qE 'define[^;]*@triple'  /tmp/h_dis.ll || fail "hidden bc lacks triple"
grep -qE 'define[^;]*@alt_run' /tmp/h_dis.ll || fail "hidden bc lacks alt_run"
grep -qE 'declare[^;]*@triple' /tmp/h_dis.ll && fail "hidden bc unresolved triple"

# ---- 3/4/5) elf.py, sym.py, solver.py behaviour on hidden inputs ----
python3 /tests/verify.py /tests/hidden || fail "verify.py failed"

echo "1" > "$R"
exit 0
