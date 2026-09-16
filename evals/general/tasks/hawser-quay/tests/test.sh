#!/bin/bash
# Verifier for hawser-quay (SWE-bench-shaped debugging task against the real
# jest monorepo, pinned to the parent commit of the %j+bigint fix).
# Checks, in order:
#   1. integrity of the verifier's own reference material (sha256 pins for the
#      pristine pre-fix table module, the golden regression test + runner, and
#      the toolchain binaries used to compile them),
#   2. the two declared deliverables: /app/reproduce.sh (executable, contract
#      reproduction) and /app/diagnosis.md (names the real module and cause),
#   3. /app/src is the real jest tree and the formatter module's source was
#      actually edited,
#   4. the module compiles standalone (both from the pristine pre-fix copy and
#      from the agent's edited tree) with the pinned toolchain,
#   5. the agent's own reproduction: must FAIL against the pre-fix formatter
#      and PASS against the repaired one (both directions, honest repro),
#   6. the project's own regression test for this bug (the authored golden
#      runner under /tests/golden, a hero-port of the three tests the upstream
#      fix added; the pristine upstream test bytes live at build time under
#      /opt/hawser-golden/array.test.ts and are never committed to this tree)
#      must pass against the repaired formatter and fail against the pre-fix
#      one. The runner is executed from the READ-ONLY /tests mount: the trial
#      agent is root in the same container as the verifier, so /opt is
#      tamperable and is NOT trusted here; /tests is a ro bind mount. The
#      embedded sha256 below is belt-and-braces against accidental drift,
#   7. every hidden case (fresh inputs the upstream tests never use) must pass
#      against the repaired formatter AND fail against the pre-fix one.
# Reward is binary and written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=0
failures=0

fail() {
    echo "FAIL: $*" >&2
    failures=1
}

# ---- 0. integrity of the verifier's own reference material ----------------
# The RO /tests mount is the authoritative, untamperable copy of the golden
# runner; the /opt copies are build-time probe artifacts and diagnostics only.
# sha256 checks below are best-effort (a root trial agent could rewrite /opt
# and these pins together, so they are not security boundaries), while the
# /tests/golden runner is itself on a read-only bind mount and cannot be
# rewritten by anyone inside the container.
( cd / && sha256sum -c /opt/pins/pristine.sha256 >/dev/null 2>&1 ) \
    || fail "pristine pre-fix table module tampered"
( cd / && sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 ) \
    || fail "golden regression-test material tampered"
( cd /opt/jest-deps && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1 ) \
    || fail "toolchain binaries tampered"
if [ ! -f /tests/golden/run-golden.sh ]; then
    fail "golden runner missing from read-only /tests mount"
else
    echo '2f54a1973351a4fb387f9590a9b96c4bc26f01b115ac61c74ee966b05f84270e  /tests/golden/run-golden.sh' \
        | sha256sum -c - >/dev/null 2>&1 \
        || fail "golden runner under /tests does not match the authored sha256"
fi

# ---- 1. deliverables --------------------------------------------------------
if [ ! -x /app/reproduce.sh ]; then
    fail "deliverable /app/reproduce.sh missing or not executable"
fi
if [ ! -s /app/diagnosis.md ]; then
    fail "deliverable /app/diagnosis.md missing or empty"
else
    python3 - /app/diagnosis.md <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
low = text.lower()
keywords = ("%j", "json placeholder", "json")
has_bigint = ("bigint" in low or "big int" in low)
names_module = ("each" in low or "parameterised" in low or "parameterized" in low)
root_cause = ("serialize" in low or "serialise" in low or "util.format" in low
              or "stringif" in low or "placeholder" in low)
ok = (len(text.strip()) >= 120
      and any(k in low for k in keywords)
      and has_bigint and names_module and root_cause)
if not ok:
    print(f"FAIL: /app/diagnosis.md does not identify the real module and cause "
          f"(len={len(text.strip())}, bigint={has_bigint}, "
          f"each/parameterised={names_module}, cause={root_cause})", file=sys.stderr)
    sys.exit(1)
print("diagnosis: acceptable (module + bigint + root cause)")
PY
    if [ $? -ne 0 ]; then
        failures=1
    fi
fi

# ---- 2. this must be the real jest tree -------------------------------------
if [ ! -f /app/src/packages/jest-each/src/table/array.ts ] \
   || [ ! -f /app/src/packages/jest-each/src/table/interpolation.ts ] \
   || [ ! -f /app/src/package.json ]; then
    fail "/app/src is not the expected jest tree (table formatter missing)"
fi
if [ -f /app/src/packages/jest-each/src/table/array.ts ] \
   && cmp -s /app/src/packages/jest-each/src/table/array.ts \
             /opt/hawser-pristine/table/array.ts; then
    fail "formatter source array.ts is byte-identical to the delivered buggy tree"
fi

# ---- 3. standalone compile of both worlds -----------------------------------
TS=/opt/jest-deps/node_modules/.bin/tsc
compile_module() {  # src_dir out_dir
    local src_from=$1 out_to=$2
    rm -rf "$out_to"
    mkdir -p "$out_to/src"
    cp "$src_from/array.ts" "$src_from/interpolation.ts" "$out_to/src/"
    ln -sfn /opt/jest-deps/node_modules "$out_to/node_modules"
    ( cd "$out_to" && "$TS" --module commonjs --target es2022 \
        --esModuleInterop --skipLibCheck --outDir out \
        src/array.ts src/interpolation.ts > /dev/null 2>&1 || true )
    [ -f "$out_to/out/array.js" ] && [ -f "$out_to/out/interpolation.js" ]
}

PRE=/tmp/vout/pre
FIXED=/tmp/vout/fixed

if ! compile_module /opt/hawser-pristine/table "$PRE"; then
    fail "pre-fix formatter did not compile with the pinned toolchain"
fi
if ! compile_module /app/src/packages/jest-each/src/table "$FIXED"; then
    fail "repaired formatter did not compile with the pinned toolchain"
fi

# ---- 4. the agent's own reproduction, both directions -----------------------
if [ -x /app/reproduce.sh ]; then
    rlog=/tmp/verifier_repro_pre.log
    if bash /app/reproduce.sh "$PRE/out" > "$rlog" 2>&1; then
        echo "WARN: reproduction exited 0 on the PRISTINE pre-fix formatter" >&2
        tail -5 "$rlog" >&2
        fail "agent reproduction does not fail against the pre-fix formatter"
    else
        echo "reproduction on pre-fix formatter: FAILS as required"
    fi
    if ! bash /app/reproduce.sh "$FIXED/out" > /tmp/verifier_repro_fixed.log 2>&1; then
        fail "agent reproduction does not pass against the repaired formatter"
        tail -8 /tmp/verifier_repro_fixed.log >&2
    else
        echo "reproduction on repaired formatter: PASS"
    fi
fi

# ---- 5. the project's own regression test (golden runner, ro-mounted) ------ 
if bash /tests/golden/run-golden.sh "$FIXED/out" > /tmp/verifier_golden.log 2>&1; then
    echo "upstream golden regression tests: PASS"
else
    echo "FAIL: upstream golden regression tests failed on repaired tree" >&2
    tail -8 /tmp/verifier_golden.log >&2
    fail "golden regression tests failed"
fi

# the golden set must genuinely fail on the pre-fix code in THIS image
if bash /tests/golden/run-golden.sh "$PRE/out" > /tmp/verifier_golden_pre.log 2>&1; then
    echo "FAIL: golden regression tests unexpectedly PASS on the pre-fix tree" >&2
    fail "golden regression tests do not discriminate"
else
    echo "golden regression tests on pre-fix tree: FAIL as required"
fi

# ---- 6. hidden cases (fresh inputs) -----------------------------------------
for case_dir in /tests/hidden/*/; do
    run="$case_dir/run.sh"
    [ -f "$run" ] || continue
    name=$(basename "$case_dir")
    if ! bash "$run" "$FIXED/out" > /tmp/verifier_hidden_fixed.log 2>&1; then
        echo "FAIL: hidden case $name failed on repaired tree" >&2
        tail -6 /tmp/verifier_hidden_fixed.log >&2
        fail "hidden case $name failed"
    else
        echo "hidden case $name on repaired tree: PASS"
    fi
    if bash "$run" "$PRE/out" > /tmp/verifier_hidden_pre.log 2>&1; then
        echo "FAIL: hidden case $name unexpectedly PASSES on pre-fix tree" >&2
        fail "hidden case $name does not discriminate"
    else
        echo "hidden case $name on pre-fix tree: FAIL as required"
    fi
done

if [ "$failures" -eq 0 ]; then
    reward=1
    echo "VERIFIER: all checks passed, reward=1"
else
    echo "VERIFIER: failures present, reward=0" >&2
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0