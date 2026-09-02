#!/usr/bin/env bash
#
# Verifier for drift-wharf. Runs as root after the agent finishes.
# Executes every deliverable and re-derives correctness from first principles,
# never from the agent's own files beyond invoking them.
set -uo pipefail
mkdir -p /logs/verifier
R=/logs/verifier/reward.txt
fail=0
report(){ if [ "$1" = "1" ]; then echo "PASS: $2"; else echo "FAIL: $2"; fail=$((fail+1)); fi; }

V=/tmp/vrfy
rm -rf "$V"; mkdir -p "$V"

# ---------------------------------------------------------------------------
# 1. All deliverables present.
# ---------------------------------------------------------------------------
ok=1
for f in /app/cc/bin/cc /app/unpack /app/pack /app/drifted.bin /app/probe.o /app/verify.txt; do
  [ -e "$f" ] || { ok=0; echo "FAIL: missing $f"; }
done
[ -s /app/verify.txt ] || { ok=0; echo "FAIL: verify.txt empty"; }
report $ok "all required deliverables present and non-empty verify.txt"

# ---------------------------------------------------------------------------
# 2. The built compiler is usable from scratch: re-invoked to compile, link
#    and run a brand-new Zephyr program (prints '1764'), and to emit a
#    relocatable object with -c. Exercises the from-source-build competency.
# ---------------------------------------------------------------------------
cat > "$V/vrf.zh" <<'ZH_EOF'
byte DIG[16];
int sq(int n){ return n * n; }
int main(){
    int v = sq(42);
    int n = 0;
    if (v == 0){ out(48); }
    while (v > 0){ DIG[n] = (48 + (v % 10)); n = n + 1; v = v / 10; }
    int i = 0;
    while (i < n){ out(DIG[n - 1 - i]); i = i + 1; }
    out(10);
    return 0;
}
ZH_EOF
ok=0
if /app/cc/bin/cc -o "$V/vrf" "$V/vrf.zh" 2>"$V/cc.err" \
   && [ -s "$V/vrf" ] && [ "$("$V/vrf")" = "1764" ]; then
  if /app/cc/bin/cc -c -o "$V/vrf.o" "$V/vrf.zh" 2>>"$V/cc.err" \
     && file "$V/vrf.o" | grep -qi relocatable; then ok=1; fi
fi
report $ok "built compiler /app/cc/bin/cc compiles, links, runs, and emits a relocatable object"

# ---------------------------------------------------------------------------
# 3. probe.o is a real object, and cardinal.h re-compiles strict-C++11.
# ---------------------------------------------------------------------------
ok=1
file /app/probe.o | grep -qi relocatable || { ok=0; echo "FAIL: probe.o is not an ELF object"; }
g++ -std=c++11 -pedantic-errors -I/app/deck -c /app/probe/probe.cpp -o "$V/p.o" 2>"$V/p.err" \
   || { ok=0; echo "FAIL: cardinal.h not strict-C++11 clean -- $(cat "$V/p.err")"; }
file "$V/p.o" | grep -qi relocatable || { ok=0; echo "FAIL: independent probe object missing"; }
report $ok "cardinal.h is strict-C++11-clean and /app/probe.o is a valid object"

# ---------------------------------------------------------------------------
# 4. End-to-end round trip over the visible corpus, re-derived independently,
#    and matching /app/verify.txt exactly.
# ---------------------------------------------------------------------------
ok=0
if /app/unpack < /app/drifted.bin > "$V/rec.bin" 2>"$V/u.err" \
   && cmp -s "$V/rec.bin" /app/data/reference.txt; then
  exp="ROUNDTRIP_OK $(sha256sum "$V/rec.bin" | awk '{print $1}')"
  got="$(cat /app/verify.txt)"
  if [ "$got" = "$exp" ]; then ok=1; else echo "FAIL: verify.txt mismatch (got='$got' expected='$exp')"; fi
else
  echo "FAIL: visible round trip diverged or unpack exited nonzero $(cat "$V/u.err")"
fi
report $ok "decoder round-trips the compressed corpus byte-for-byte with matching verify.txt"

# ---------------------------------------------------------------------------
# 5. Hidden generalization: pack + unpack each hidden payload round-trips it.
# ---------------------------------------------------------------------------
hidden_total=0; hidden_good=0
for f in /tests/hidden/*; do
  [ -e "$f" ] || continue
  hidden_total=$((hidden_total + 1))
  if /app/pack < "$f" > "$V/h.bin" 2>"$V/h.err" \
     && /app/unpack < "$V/h.bin" > "$V/h.out" 2>/dev/null \
     && cmp -s "$V/h.out" "$f"; then
    hidden_good=$((hidden_good + 1))
  else
    echo "FAIL: hidden payload $(basename "$f") did not round-trip: $(cat "$V/h.err")"
  fi
done
ok=0
if [ "$hidden_total" -ge 2 ] && [ "$hidden_good" -eq "$hidden_total" ]; then ok=1; fi
report $ok "encoder generalizes: exact byte round-trip on $hidden_good/$hidden_total hidden payloads"

# ---------------------------------------------------------------------------
if [ "$fail" = "0" ]; then echo "1" > "$R"; else echo "0" > "$R"; fi
echo "VERIFIER_COMPLETE failures=$fail reward=$(cat "$R")"