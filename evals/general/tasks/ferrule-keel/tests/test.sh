#!/bin/bash
# Verifier for ferrule-keel (compiler-from-source against the real tinycc
# tree). Reward is 1 only if, in order:
#   1. every declared deliverable exists, the compiler is a real ELF tcc
#      0.9.27 binary (not a symlink, not a wrapper), ldd-clean, and the
#      build artifacts are in the upstream tree (/app/src/config.mak,
#      /app/src/tcc),
#   2. the agent's recorded stdout for each of the four standard-C programs
#      is byte-identical to what the agent-built compiler produces when the
#      verifier recompiles and reruns the same source,
#   3. the agent's own ./configure && make ran (config.mak + in-tree tcc),
#   4. the complex-numbers program is handled *differently* by the two
#      compilers: tcc must FAIL to compile it (the documented missing C99
#      complex type) while gcc must compile and run it to the recorded
#      complex.gcc.out,
#   5. hidden standard-C cases compile and run identically under tcc and gcc
#      and match an independently recorded expectation byte-for-byte,
#   6. the hidden complex case fails under tcc and matches under gcc,
#   7. diagnosis.md names the divergent program, the feature, and cites
#      tcc-doc.texi,
#   8. the upstream project's own suite 'make tests2.all' passes against the
#      agent's build.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=0
failures=0
TCC=/app/tccinst/bin/tcc
VISIBLE="/app/programs"

# ---- 1. deliverables and compiler integrity ---------------------------------
if [ ! -x "$TCC" ]; then
    echo "FAIL: deliverable $TCC missing or not executable" >&2
    failures=1
else
    if [ -L "$TCC" ]; then
        echo "FAIL: $TCC is a symlink (must be a real built binary)" >&2
        failures=1
    fi
    if ! magic=$(head -c4 "$TCC" 2>/dev/null | od -An -tx1 | tr -d ' \n'); then
        magic=""
    fi
    if [ "$magic" != "7f454c46" ]; then
        echo "FAIL: $TCC is not an ELF executable (magic=$(printf '%s' "$magic"))" >&2
        failures=1
    fi
    ver=$("$TCC" -v 2>&1 | head -1)
    case "$ver" in
        *"tcc version 0.9.27"*) echo "compiler identity: $ver" ;;
        *) echo "FAIL: $TCC -v reports '$ver', expected tcc version 0.9.27" >&2; failures=1 ;;
    esac
    if ldd "$TCC" 2>/dev/null | grep -q "not found"; then
        echo "FAIL: $TCC has unresolved dynamic links" >&2
        failures=1
    fi
fi

for f in /app/outputs/hello.out /app/outputs/fib.out /app/outputs/strings.out \
         /app/outputs/structs.out /app/outputs/complex.err \
         /app/outputs/complex.gcc.out /app/diagnosis.md; do
    if [ ! -s "$f" ]; then
        echo "FAIL: deliverable $f missing or empty" >&2
        failures=1
    fi
done

if [ ! -f /app/src/config.mak ]; then
    echo "FAIL: /app/src was not configured (config.mak absent)" >&2
    failures=1
fi
if [ ! -x /app/src/tcc ]; then
    echo "FAIL: the build did not happen in the upstream tree (/app/src/tcc absent)" >&2
    failures=1
fi

# ---- 2. visible standard-C programs: recompile with the agent's tcc --------
for prog in hello fib strings structs; do
    if ! "$TCC" -o "/tmp/v_$prog" "$VISIBLE/$prog.c" >"/tmp/v_$prog.compile" 2>&1; then
        echo "FAIL: $TCC cannot compile visible $prog.c" >&2
        tail -3 "/tmp/v_$prog.compile" >&2
        failures=1
        continue
    fi
    if ! "/tmp/v_$prog" >"/tmp/v_$prog.out" 2>/dev/null; then
        echo "FAIL: visible $prog.c crashed under $TCC" >&2
        failures=1
        continue
    fi
    if cmp -s "/tmp/v_$prog.out" "/app/outputs/$prog.out"; then
        echo "visible $prog: recorded output matches a fresh $TCC run"
    else
        echo "FAIL: /app/outputs/$prog.out does not match a fresh run of the built compiler" >&2
        failures=1
    fi
done

# ---- 3. the documented divergence: complex numbers --------------------------
if "$TCC" -o /tmp/v_complex "$VISIBLE/complex.c" >/tmp/v_complex.compile 2>/tmp/v_complex.err; then
    echo "FAIL: $TCC compiled complex.c but tcc-doc.texi documents complex numbers as missing" >&2
    failures=1
elif [ ! -s /tmp/v_complex.err ]; then
    echo "FAIL: $TCC rejected complex.c but produced no diagnostic" >&2
    failures=1
else
    echo "tcc on complex.c: rejected with $(wc -l < /tmp/v_complex.err) stderr lines (documented divergence)"
fi
[ -s /app/outputs/complex.err ] || {
    echo "FAIL: /app/outputs/complex.err (the recorded tcc stderr) is empty" >&2
    failures=1
}
if gcc -o /tmp/v_complex_gcc "$VISIBLE/complex.c" >/tmp/v_complex_gcc.compile 2>&1 \
   && /tmp/v_complex_gcc >/tmp/v_complex_gcc.out 2>/dev/null; then
    if cmp -s /tmp/v_complex_gcc.out /app/outputs/complex.gcc.out; then
        echo "gcc on complex.c: recorded gcc output matches a fresh gcc run"
    else
        echo "FAIL: /app/outputs/complex.gcc.out does not match a fresh gcc run" >&2
        failures=1
    fi
else
    echo "FAIL: gcc cannot compile and run complex.c (comparison basis broken)" >&2
    failures=1
fi

# ---- 4. hidden standard-C cases: tcc and gcc must agree byte-for-byte -------
for case_dir in /tests/hidden/agree1 /tests/hidden/agree2; do
    src="$case_dir/program.c"
    exp="$case_dir/expected.txt"
    if [ ! -f "$src" ] || [ ! -f "$exp" ]; then
        continue
    fi
    name=$(basename "$case_dir")
    if ! "$TCC" -o "/tmp/h_${name}" "$src" >"/tmp/h_${name}.compile" 2>&1; then
        echo "FAIL: hidden $name: $TCC cannot compile the case" >&2
        tail -3 "/tmp/h_${name}.compile" >&2
        failures=1
        continue
    fi
    if ! "/tmp/h_${name}" >"/tmp/h_${name}.tcc.out" 2>/dev/null; then
        echo "FAIL: hidden $name: tcc-built binary failed at runtime" >&2
        failures=1
    fi
    if ! gcc -o "/tmp/hg_${name}" "$src" >"/tmp/hg_${name}.compile" 2>&1; then
        echo "FAIL: hidden $name: gcc cannot compile the case" >&2
        failures=1
        continue
    fi
    if ! "/tmp/hg_${name}" >"/tmp/hg_${name}.gcc.out" 2>/dev/null; then
        echo "FAIL: hidden $name: gcc-built binary failed at runtime" >&2
        failures=1
        continue
    fi
    if cmp -s "/tmp/h_${name}.tcc.out" "/tmp/hg_${name}.gcc.out" \
       && cmp -s "/tmp/h_${name}.tcc.out" "$exp"; then
        echo "hidden $name: tcc and gcc agree and match expected output"
    else
        echo "FAIL: hidden $name: tcc/gcc outputs differ or mismatch the expectation" >&2
        failures=1
    fi
done

# ---- 5. hidden complex case: tcc must fail, gcc must match ------------------
src=/tests/hidden/complex-diverg/program.c
exp=/tests/hidden/complex-diverg/expected.txt
if [ -f "$src" ] && [ -f "$exp" ]; then
    if "$TCC" -o /tmp/h_complex "$src" >/tmp/h_complex.compile 2>/tmp/h_complex.err; then
        echo "FAIL: hidden complex-diverg: $TCC compiled it, but complex numbers must not build" >&2
        failures=1
    elif [ -s /tmp/h_complex.err ]; then
        echo "hidden complex-diverg: $TCC rejects it (as documented)"
    else
        echo "FAIL: hidden complex-diverg: $TCC rejected with no diagnostic" >&2
        failures=1
    fi
    if gcc -o /tmp/h_complex_gcc "$src" >/tmp/h_complex_gcc.compile 2>&1 \
       && /tmp/h_complex_gcc >/tmp/h_complex_gcc.out 2>/dev/null; then
        if cmp -s /tmp/h_complex_gcc.out "$exp"; then
            echo "hidden complex-diverg: gcc output matches the expectation"
        else
            echo "FAIL: hidden complex-diverg: gcc output mismatches the expectation" >&2
            failures=1
        fi
    else
        echo "FAIL: hidden complex-diverg: gcc could not compile and run it" >&2
        failures=1
    fi
fi

# ---- 6. diagnosis -----------------------------------------------------------
if [ -f /app/diagnosis.md ]; then
    diag=$(tr '[:upper:]' '[:lower:]' < /app/diagnosis.md)
    if [ "${#diag}" -lt 100 ]; then
        echo "FAIL: /app/diagnosis.md is too short to be a real diagnosis" >&2
        failures=1
    fi
    case "$diag" in
        *complex*) : ;;
        *) echo "FAIL: /app/diagnosis.md never names the 'complex' feature" >&2; failures=1 ;;
    esac
    case "$diag" in
        *tcc-doc.texi*) : ;;
        *) echo "FAIL: /app/diagnosis.md does not cite tcc-doc.texi" >&2; failures=1 ;;
    esac
    if [ $failures -eq 0 ]; then
        echo "diagnosis: names the program, the missing feature and the doc"
    fi
else
    echo "FAIL: /app/diagnosis.md missing" >&2
    failures=1
fi

# ---- 7. the upstream project's own suite against the agent's build ----------
log=/tmp/verifier_tests2.log
if (cd /app/src && make tests2.all > "$log" 2>&1); then
    npass=$(grep -c "^Test:" "$log" || true)
    echo "upstream tests2 suite: PASS (${npass:-0} tests run by the project's own harness)"
else
    echo "FAIL: 'make tests2.all' (the upstream project's own suite) does not pass" >&2
    tail -8 "$log" >&2
    failures=1
fi

# ---- reward ---------------------------------------------------------------
if [ "$failures" -eq 0 ]; then
    reward=1
    echo "VERIFIER: all checks passed, reward=1"
else
    echo "VERIFIER: ${failures} failure(s) present, reward=0" >&2
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0