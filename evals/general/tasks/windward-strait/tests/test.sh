#!/bin/bash
# Verifier for windward-strait (real-upstream debugging task, scipy trust-
# region solvers). Checks, in order:
#   1. the three declared deliverables exist (/app/reproduce.py, /app/
#      diagnosis.md, repaired /app/src),
#   2. /app/reproduce.py genuinely drives the installed library (must
#      reference scipy.optimize and a trust-region method),
#   3. the agent actually changed library source and touched no test file,
#   4. the agent's reproduction FAILS against the pristine (pre-fix) library
#      -- proven by restoring the single buggy module from the git HEAD --
#      and PASSES against the repaired tree,
#   5. the upstream regression test (extracted from the fix commit at image
#      build time into /opt/scipy-golden/) is injected into the project's own
#      test file and the whole trust-region test suite must pass,
#   6. every hidden case must PASS on the repaired tree AND FAIL on the
#      pristine tree (each hidden case is a genuine regression test),
#   7. /app/diagnosis.md names the real module and root cause.
# Reward is binary, written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=0
failures=0

SRC="/app/src/scipy/optimize/_trustregion.py"
TESTFILE="/app/src/scipy/optimize/tests/test_trustregion.py"
AGENT_BACKUP="/tmp/agent_trustregion.py"
GOLDEN="/opt/scipy-golden/golden_append.py"

restore_pristine() {
    # Rewrite the single buggy module to the exact pre-fix (HEAD) revision.
    git -C /app/src show HEAD:scipy/optimize/_trustregion.py > "$SRC" 2>/dev/null
}
restore_agent() {
    cp "$AGENT_BACKUP" "$SRC"
}

# ---- 1. deliverables -------------------------------------------------------
[ -f /app/reproduce.py ] || { echo "FAIL: deliverable /app/reproduce.py missing" >&2; failures=1; }
[ -f /app/diagnosis.md ] || { echo "FAIL: deliverable /app/diagnosis.md missing" >&2; failures=1; }
[ -f "$SRC" ] || { echo "FAIL: /app/src is not the library tree (/app/src/scipy/optimize/_trustregion.py missing)" >&2; failures=1; }

# ---- 3. the agent changed library source and touched no test file ---------
if [ -d /app/src ]; then
    status=$(git -C /app/src status --porcelain 2>/dev/null)
    if [ -z "$status" ]; then
        echo "FAIL: no changes in /app/src (the library was not repaired)" >&2
        failures=1
    fi
    if echo "$status" | grep -q "scipy/optimize/tests"; then
        echo "FAIL: the agent modified files under scipy/optimize/tests (forbidden)" >&2
        failures=1
    fi
fi

# ---- 2. reproduction contract checks --------------------------------------
if [ -f /app/reproduce.py ]; then
    if ! grep -q "scipy.optimize" /app/reproduce.py; then
        echo "FAIL: /app/reproduce.py does not import/use scipy.optimize" >&2
        failures=1
    fi
    if ! grep -q "trust-exact" /app/reproduce.py; then
        echo "FAIL: /app/reproduce.py does not exercise a trust-region method" >&2
        failures=1
    fi
fi

# ---- 4. reproduction, both directions -------------------------------------
if [ -f "$SRC" ] && [ -f /app/reproduce.py ]; then
    cp "$SRC" "$AGENT_BACKUP"

    restore_pristine
    if python3 /app/reproduce.py > /tmp/repro_pristine.log 2>&1; then
        echo "FAIL: agent reproduction exits 0 on the PRISTINE (pre-fix) library; it does not demonstrate the bug" >&2
        cat /tmp/repro_pristine.log >&2
        failures=1
    else
        echo "reproduction vs pristine library: FAILS as required (rc=$?; $(head -1 /tmp/repro_pristine.log))"
    fi

    restore_agent
    if python3 /app/reproduce.py > /tmp/repro_fixed.log 2>&1; then
        echo "reproduction vs repaired tree: PASSES ($(head -1 /tmp/repro_fixed.log))"
    else
        echo "FAIL: agent reproduction exits non-zero on the repaired tree" >&2
        cat /tmp/repro_fixed.log >&2
        failures=1
    fi
fi

# ---- 5. upstream regression test + the project's own suite ----------------
if [ -d /app/src ]; then
    if [ -f "$GOLDEN" ]; then
        git -C /app/src show HEAD:scipy/optimize/tests/test_trustregion.py > "$TESTFILE" 2>/dev/null
        cat "$GOLDEN" >> "$TESTFILE"
        log=/tmp/verifier_trustregion.log
        if (cd /app/src && python3 -m pytest -q scipy/optimize/tests/test_trustregion.py -p no:cacheprovider > "$log" 2>&1); then
            echo "scipy own test_trustregion.py (incl. injected upstream regression test): PASS ($(tail -1 "$log"))"
        else
            echo "FAIL: scipy's own trust-region test suite does not pass on the repaired tree" >&2
            tail -12 "$log" >&2
            failures=1
        fi
    else
        echo "FAIL: golden test file $GOLDEN missing from image" >&2
        failures=1
    fi
fi

# ---- 6. hidden cases, both directions --------------------------------------
for case_dir in /tests/hidden/*/; do
    run="$case_dir/run.py"
    [ -f "$run" ] || continue
    name=$(basename "$case_dir")
    hlog=/tmp/verifier_hidden_${name}.log
    # (a) must pass on the repaired tree
    if [ -f "$SRC" ]; then
        cp "$SRC" "$AGENT_BACKUP"
    fi
    if (cd /app/src && python3 "$run" > "$hlog" 2>&1); then
        echo "hidden case $name vs repaired tree: PASS"
    else
        echo "FAIL: hidden case $name does not pass on the repaired tree" >&2
        tail -6 "$hlog" >&2
        failures=1
    fi
    # (b) must fail on the pristine tree (genuine regression tests)
    if [ -f "$SRC" ]; then
        restore_pristine
        if (cd /app/src && python3 "$run" > "$hlog" 2>&1); then
            echo "FAIL: hidden case $name passes even on the PRISTINE (pre-fix) library; it is not a real regression test" >&2
            failures=1
        else
            echo "hidden case $name vs pristine library: FAILS as required"
        fi
        restore_agent
    fi
done

# ---- 7. diagnosis content --------------------------------------------------
if [ -f /app/diagnosis.md ]; then
    python3 - /app/diagnosis.md <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
low = text.lower()
ok = (len(text.strip()) >= 150
      and "trustregion" in low.replace("-", ".")
      and "hessian" in low
      and "nan" in low
      and "proposed" in low
      and ("radius" in low or "radii" in low))
if not ok:
    print("FAIL: /app/diagnosis.md does not state the real module and root "
          f"cause (len={len(text.strip())}, trustregion="
          f"{'trustregion' in low.replace('-', '.')}, hessian={'hessian' in low}, "
          f"nan={'nan' in low}, proposed={'proposed' in low}, "
          f"radius={'radius' in low or 'radii' in low})", file=sys.stderr)
    sys.exit(1)
print("diagnosis: acceptable (names module + root cause + fix)")
PY
    [ $? -eq 0 ] || failures=1
fi

# ---- verdict ----------------------------------------------------------------
if [ $failures -eq 0 ]; then
    reward=1
    echo "VERIFIER: all checks passed, reward=1"
else
    echo "VERIFIER: failures present, reward=0" >&2
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0