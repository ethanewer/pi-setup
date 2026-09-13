#!/bin/bash
# Oracle for capstan-foresheet: applies the minimal upstream-style fix to the
# real Z3Prover/z3 tree at /app/src (widen the fp.rem significand arithmetic
# so a subnormal divisor cannot shift the dividend's high bits out), writes
# /app/summary.md, then proves the work with the project's own machinery:
# rebuild the solver, plant the upstream regression test baked at
# /opt/golden, rebuild and run the project's own test harness (the new fpa
# module and the full unit suite), and re-run the visible reproductions, all
# offline. Reads only /app, /solution and /opt/golden, never /tests. The
# planted golden files are restored afterwards so the tree is left exactly as
# the verifier expects: pinned parent + the single fixed source file.
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied fp.rem subnormal-divisor significand-widening fix"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: Z3 computed a wrong IEEE 754 remainder for `fp.rem` whenever the
divisor is a subnormal floating-point number. With both operands pinned to
concrete binary16 patterns, the query
`(assert (not (= ((_ fp.to_ieee_bv 16) (fp.rem x y)) #x000a)))` answered
`sat` where the operands fully determine the operation and the answer must be
`unsat`; the bit-vector encoding the fpa2bv pipeline computed for the
remainder was the encoding of negative zero (#x8000) instead of the true
remainder (#x000a).

Root cause: in the fpa2bv conversion of `fp.rem`
(`fpa2bv_converter::mk_rem` in `src/ast/fpa/fpa2bv_converter.cpp`), the two
significands are zero-extended by `max_exp_diff = 2^ebits - 3` bits in order
to compute `x rem y` by fixed-point division. That width covers the largest
possible exponent difference between two *normal* or exponent-bounded
operands, but a subnormal divisor has no implicit leading one: its normalized
exponent sits `sbits - 1` binary places below min-exponent, so the actual
(exponent - leading-zeros) difference with a large normal dividend can exceed
`max_exp_diff`. When the shift that aligns the exponents is then larger than
the widened dividend allows, the high-order bits of the dividend are shifted
out before the remainder is computed and the computed value is garbage
(here, -0.0/#x8000).

Fix: widen both significands by `sig_ext_amount = max_exp_diff + sbits - 1`
(covering a subnormal divisor's lost bits as well), drive the zero-extension
loop and the subsequent shift-operand sizing from `sig_ext_amount` instead of
`max_exp_diff`, and keep the same overflow guard. No other code is touched;
`fp.rem` with normal divisors and every other floating-point operation behave
exactly as before.

Verification: rebuilt the solver and the project's own test harness
(`cmake --build build --target shell`, then `test-z3` after planting the
upstream regression test `src/test/fpa.cpp` from /opt/golden with the two
one-line registrations the fix commit performs). The project's own regression
test (`./build/test-z3 fpa`) passes; the project's entire unit suite
(`./build/test-z3 -a`) passes (N passed, 0 failed); and the three visible
repro queries all print `unsat`.
MD

# Prove the fix with the project's own machinery: rebuild the solver (the
# agent-facing binary), plant the upstream regression test (golden bytes from
# /opt/golden, already in the image), rebuild the harness offline and run the
# new fpa module plus the whole existing unit suite.
if ! cmake --build build --target shell -j1 > /tmp/oracle_shell.log 2>&1; then
    echo "oracle: shell rebuild failed; tail:" >&2
    tail -30 /tmp/oracle_shell.log >&2
    exit 1
fi
bash /app/plant_golden.sh || { echo "oracle: could not plant golden test" >&2; exit 1; }
if ! cmake --build build --target test-z3 -j1 > /tmp/oracle_tz.log 2>&1; then
    echo "oracle: test-z3 rebuild failed; tail:" >&2
    tail -30 /tmp/oracle_tz.log >&2
    exit 1
fi

if ! ./build/test-z3 fpa > /tmp/oracle_fpa.log 2>&1; then
    echo "oracle: upstream regression test did not pass; tail:" >&2
    tail -20 /tmp/oracle_fpa.log >&2
    exit 1
fi
grep -q "PASS" /tmp/oracle_fpa.log || {
    echo "oracle: fpa regression test did not actually run" >&2
    exit 1
}

if ! ./build/test-z3 -a > /tmp/oracle_all.log 2>&1; then
    echo "oracle: full unit suite did not pass; tail:" >&2
    tail -30 /tmp/oracle_all.log >&2
    exit 1
fi
grep -Eq "0 failed" /tmp/oracle_all.log || {
    echo "oracle: full unit suite summary not as expected" >&2
    tail -10 /tmp/oracle_all.log >&2
    exit 1
}

# Direct reproductions through the agent-facing binary.
check_query() { # file expected
    got=$(./build/z3 "$1")
    [ "$got" = "$2" ] || {
        echo "oracle: repro $1: got '$got', expected '$2'" >&2
        exit 1
    }
}
cat > /tmp/oracle_repro.smt2 <<'EOF'
(declare-const x (_ FloatingPoint 5 11))
(declare-const y (_ FloatingPoint 5 11))
(assert (= x ((_ to_fp 5 11) #b1110100000101010)))
(assert (= y ((_ to_fp 5 11) #b1000000000010101)))
(assert (not (= ((_ fp.to_ieee_bv 16) (fp.rem x y)) #x000a)))
(check-sat-using (then fpa2bv simplify bit-blast smt))
EOF
cat > /tmp/oracle_v1.smt2 <<'EOF'
(declare-const x (_ FloatingPoint 5 11))
(declare-const y (_ FloatingPoint 5 11))
(assert (= x ((_ to_fp 5 11) #b0101100000000001)))
(assert (= y ((_ to_fp 5 11) #b0000000000000011)))
(assert (not (= ((_ fp.to_ieee_bv 16) (fp.rem x y)) #x0001)))
(check-sat-using (then fpa2bv simplify bit-blast smt))
EOF
cat > /tmp/oracle_v2.smt2 <<'EOF'
(declare-const x (_ FloatingPoint 5 11))
(declare-const y (_ FloatingPoint 5 11))
(assert (= x ((_ to_fp 5 11) #b1111010000000000)))
(assert (= y ((_ to_fp 5 11) #b1000000001000001)))
(assert (not (= ((_ fp.to_ieee_bv 16) (fp.rem x y)) #x8004)))
(check-sat-using (then fpa2bv simplify bit-blast smt))
EOF
check_query /tmp/oracle_repro.smt2 unsat
check_query /tmp/oracle_v1.smt2 unsat
check_query /tmp/oracle_v2.smt2 unsat
echo "oracle: direct reproductions OK"

# Leave the tree exactly as the verifier expects it: the regression test and
# registrations were planted here only to prove the fix and must not persist
# (the verifier re-plants them itself and asserts every tracked file except
# the fixed source file is byte-identical to the pinned commit).
cd /app/src || exit 1
git restore --worktree --source=HEAD -- src/test/main.cpp src/test/CMakeLists.txt || {
    echo "oracle: could not restore src/test files" >&2
    exit 1
}
rm -f src/test/fpa.cpp
changed=$(git status --porcelain)
if [ "$changed" != " M src/ast/fpa/fpa2bv_converter.cpp" ]; then
    echo "oracle: unexpected working-tree state:" >&2
    echo "$changed" >&2
    exit 1
fi

echo "oracle: fix applied, summary written, regression suite green, repros OK"
exit 0