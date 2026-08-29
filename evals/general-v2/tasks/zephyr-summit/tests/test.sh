#!/usr/bin/env bash
# Zephyr Summit verifier: exercises every deliverable on visible + hidden inputs.
set -uo pipefail
mkdir -p /logs/verifier
REWARD=0
FAILED=0
fail() { echo "FAIL: $1"; FAILED=1; }

check() { # name expected actual -> diff and pass/fail
  local name="$1" exp="$2" act="$3"
  if diff -u "$exp" "$act" >/dev/null 2>&1; then
    echo "ok: $name"
  else
    echo "FAIL: $name (diff below)"; diff -u "$exp" "$act" 2>&1 | head -40; FAILED=1
  fi
}

echo "== deliverable presence =="
for f in /app/vendor/bin/cc /app/sections.txt /app/proofs/thm /app/proofs/thm.v /app/proofs/thm.vo /app/artifact/runner.jar /app/bin/symexec; do
  if [ -e "$f" ]; then echo "ok present: $f"; else echo "FAIL missing: $f"; FAILED=1; fi
done

echo "== 1. compiler: hidden C programs =="
for src in /tests/hidden/cc/*.c; do
  base=$(basename "$src" .c)
  exp="/tests/hidden/cc/$base.out"
  out="/tmp/$base.out"
  bin="/tmp/$base.bin"
  if /app/vendor/bin/cc -o "$bin" "$src" 2>/tmp/ccerr && "$bin" >"$out" 2>&1; then
    check "cc-$base" "$exp" "$out"
  else
    echo "FAIL cc-$base (compile/run)"; cat /tmp/ccerr; FAILED=1
  fi
done

echo "== 2. sections.txt : recompile probe and diff readelf dump =="
if /app/vendor/bin/cc -o /tmp/probe /app/fixtures/probe.c 2>/dev/null; then
  { readelf --wide --sections /tmp/probe; printf '\n== SYMBOLS ==\n'; readelf --wide --syms /tmp/probe; } > /tmp/sections.ref
  check "sections.txt" /tmp/sections.ref /app/sections.txt
else
  echo "FAIL sections recompile"; FAILED=1
fi

echo "== 3. coq proof object =="
mkdir -p /tmp/coqre
cp /app/proofs/thm.v /tmp/coqre/thm.v
if ( cd /tmp/coqre && coqc thm.v ) 2>/tmp/coqerr; then
  echo "ok: fresh coqc /app/proofs/thm.v compiles"
else
  echo "FAIL: fresh coqc failed"; cat /tmp/coqerr | head; FAILED=1
fi
if grep -E 'Admitted|admit|Axiom|TODO' /app/proofs/thm.v >/dev/null 2>&1; then
  echo "FAIL: /app/proofs/thm.v still contains a placeholder"; FAILED=1
else
  echo "ok: no placeholders (Admitted/admit/Axiom/TODO) in /app/proofs/thm.v"
fi
if [ -f /tmp/coqre/thm.vo ] && cmp -s /app/proofs/thm.vo /tmp/coqre/thm.vo && cmp -s /app/proofs/thm /tmp/coqre/thm.vo && [ -s /app/proofs/thm ]; then
  echo "ok: deliverable matches fresh compile (byte-identical)"
else
  echo "FAIL: /app/proofs/thm.vo or /app/proofs/thm does not match a fresh compile"; FAILED=1
fi

echo "== 4. scala assembly jar =="
run_scala() { # args... expected
  local expected="$1"; shift
  local got out
  got=$(java -jar /app/artifact/runner.jar "$@" 2>/dev/null)
  if [ "$got" = "$expected" ]; then echo "ok: scala[$*] -> $got"; else echo "FAIL: scala[$*] got '$got' expected '$expected'"; FAILED=1; fi
}
run_scala "RESULT 47" 2 3
run_scala "RESULT 17" 0 1 1
run_scala "RESULT 11" 0 0 1

echo "== 5. symbolic engine (hidden IRs) =="
if /app/bin/symexec --selftest > /tmp/selftest 2>&1; then
  if grep -q '^SELFTEST_OK' /tmp/selftest && grep -q 'llvm16=yes' /tmp/selftest; then
    echo "ok: --selftest -> $(cat /tmp/selftest)"
  else
    echo "FAIL: selftest missing llvm16=yes / SELFTEST_OK"; cat /tmp/selftest; FAILED=1
  fi
else
  echo "FAIL: --selftest exited non-zero"; cat /tmp/selftest; FAILED=1
fi
for h in /tests/hidden/sym/h1.json /tests/hidden/sym/h2.json /tests/hidden/sym/h3.json; do
  base=$(basename "$h" .json)
  exp="/tests/hidden/sym/$base.out"
  act="/tmp/$base.sym"
  if symexec "$h" >"$act" 2>&1; then
    check "sym-$base" "$exp" "$act"
  else
    echo "FAIL: sym-$base (engine errored)"; cat "$act"; FAILED=1
  fi
done

if [ "$FAILED" = "0" ]; then REWARD=1; fi
echo "REWARD=$REWARD"
echo "$REWARD" > /logs/verifier/reward.txt
exit 0
