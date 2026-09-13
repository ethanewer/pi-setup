#!/bin/bash
# Verifier for capstan-bollard: SWE-bench-shaped debugging task on the real
# scipy/scipy tree. The agent must repair /app/src so that repr() of optimizer
# result objects with empty-dict fields stops raising
# "ValueError: max() iterable argument is empty".
#
# Checks, in order:
#   1. provenance: /app/src is the real scipy tree (marker files present, no
#      git metadata, config/init/test files pristine, and the shared dict-repr
#      helper _util.py differs from the buggy parent revision -> the fix lives
#      in the tree, not in a site-packages hack),
#   2. the image's /opt/golden holds the project's OWN regression test
#      extracted verbatim from the upstream fix commit (checksum asserted),
#   3. the declared deliverable /app/reproduce.py executes and exits 0 with a
#      normal repr,
#   4. the golden regression test passes against the agent's repaired tree,
#   5. enough of the project's own existing suite passes to prove the fix
#      broke nothing else (whole TestOptimizeResultAttributes class, plus the
#      full unit-module suite of the changed helper, scipy/_lib/tests/
#      test__util.py),
#   6. every hidden case passes: three authored checks that hit the same code
#      path from inputs the upstream test does not use.
# Reward is written on every exit path and is strictly a 0 or a 1.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
failures=0

echo "== capstan-bollard verifier =="

# ---- 1. provenance: real tree, no git metadata, files in expected state ----
if [ ! -f /app/src/scipy/_lib/_util.py ] \
   || [ ! -f /app/src/scipy/optimize/_optimize.py ] \
   || [ ! -f /app/src/meson.build ] \
   || [ ! -f /app/src/pyproject.toml ]; then
    echo "FAIL: /app/src is not the scipy source tree" >&2
    failures=1
fi
if [ -d /app/src/.git ]; then
    echo "FAIL: git metadata left in /app/src: the tree must be a plain" >&2
    echo "      checkout, not history an agent could mine for answers" >&2
    failures=1
fi
# Config, package init and test files must be byte-identical to the pristine
# parent tree. This catches an agent that edits tests or metadata to fake a
# pass. The regression test file test_optimize.py is deliberately not listed:
# the verifier replaces it with the project's own regression test below.
python3 - <<'PY'
import hashlib, sys
pristine = {
"meson.build": "ae2fe6fbd554fc3286b2640a93c418df16e628d5f72e6be4cb9ca1eee7c8621c",
"pyproject.toml": "983f182a452114e0a7b97052a5a15c4457ded4c3f8dbfb0451f8b111d022eb61",
"scipy/__init__.py": "1d2b845350614addae0f58b4444b6baf1967e785ab0af89d0844f56763c16a0f",
"scipy/optimize/__init__.py": "56b3bd17b0085e3464c7f6295d59080866ca9789be9d7053caf7c03f1a12b179",
"scipy/_lib/tests/test__util.py": "45a09dc6e3f5f4f5d9b8c71bd61b52a605f112256340d642abd471842a732903",
}
bad = []
for rel, want in pristine.items():
    p = "/app/src/" + rel
    try:
        got = hashlib.sha256(open(p, "rb").read()).hexdigest()
    except OSError as e:
        bad.append(rel + " (missing: %s)" % e)
        continue
    if got != want:
        bad.append(rel)
if bad:
    print("FAIL: pristine files modified: %d (%s)" % (len(bad), "; ".join(bad[:6])), file=sys.stderr)
    sys.exit(1)
# The dict-repr helper must differ from the buggy parent revision: the repair
# has to be made in the tree, not only in the installed copy.
p = "/app/src/scipy/_lib/_util.py"
got = hashlib.sha256(open(p, "rb").read()).hexdigest()
if got == "947a56c670bc6e4f0a14fe94f91cf852eba8d633ddc9bf7bcec257baf10b207f":
    print("FAIL: scipy/_lib/_util.py is byte-identical to the buggy parent", file=sys.stderr)
    print("      revision: the tree has not been repaired", file=sys.stderr)
    sys.exit(1)
print("provenance: real tree, no .git, key files untouched, helper changed")
PY
rc=$?
if [ $rc -ne 0 ]; then
    failures=1
fi

# ---- 2. golden regression test: present and untampered ---------------------
GOLD="d19d3926dc4a0984c1a27278d2102114d3d5dcacd52c4954e2dbddfe079211cb"
if [ ! -f /opt/golden/test_optimize.py ]; then
    echo "FAIL: /opt/golden is missing the project's regression test file" >&2
    failures=1
else
    h=$(sha256sum /opt/golden/test_optimize.py | awk '{print $1}')
    if [ "$h" != "$GOLD" ]; then
        echo "FAIL: /opt/golden/test_optimize.py does not match the upstream" >&2
        echo "      fix-commit file (tampered golden copy)" >&2
        failures=1
    else
        echo "golden: regression test file intact"
    fi
fi

# ---- 3. declared deliverable /app/reproduce.py executes --------------------
if [ ! -f /app/reproduce.py ]; then
    echo "FAIL: deliverable /app/reproduce.py missing" >&2
    failures=1
else
    if python3 /app/reproduce.py > /tmp/verifier_repro.out 2>&1; then
        if grep -q 'options' /tmp/verifier_repro.out; then
            echo "reproduce.py: PASS (prints a normal repr)"
        else
            echo "FAIL: /app/reproduce.py exited 0 but its output does not show" >&2
            echo "      the result object" >&2
            tail -5 /tmp/verifier_repro.out >&2
            failures=1
        fi
    else
        echo "FAIL: /app/reproduce.py still crashes" >&2
        tail -8 /tmp/verifier_repro.out >&2
        failures=1
    fi
fi

# ---- 4. the project's own regression test against the repaired tree --------
# Replace the tree's test file with the project's regression version from the
# fix commit (whatever pristine or agent-edited bytes were there), then run
# the upstream test by its upstream name.
if [ $failures -eq 0 ]; then
    mkdir -p /app/src/scipy/optimize/tests
    cp /opt/golden/test_optimize.py /app/src/scipy/optimize/tests/test_optimize.py
    (
        cd /app/src &&
        python3 -m pytest \
            'scipy/optimize/tests/test_optimize.py::TestOptimizeResultAttributes::test_repr_with_empty_dict_value' \
            -q --no-header
    ) > /tmp/verifier_golden.log 2>&1
    if [ $? -eq 0 ]; then
        echo "golden regression test: PASS"
    else
        echo "FAIL: golden regression test test_repr_with_empty_dict_value failed" >&2
        tail -20 /tmp/verifier_golden.log >&2
        failures=1
    fi

    # 4b. existing project suites that must keep passing: the whole class that
    # owns the repr behaviour, and the full module suite of the changed helper.
    (
        cd /app/src &&
        python3 -m pytest \
            'scipy/optimize/tests/test_optimize.py::TestOptimizeResultAttributes' \
            -q --no-header
    ) > /tmp/verifier_class.log 2>&1
    if [ $? -eq 0 ]; then
        echo "TestOptimizeResultAttributes class: PASS ($(grep -E '^[0-9]+ (passed|failed)' /tmp/verifier_class.log | tr '\n' ' '))"
    else
        echo "FAIL: project class TestOptimizeResultAttributes does not pass" >&2
        tail -15 /tmp/verifier_class.log >&2
        failures=1
    fi

    (
        cd /app/src &&
        python3 -m pytest scipy/_lib/tests/test__util.py -q --no-header
    ) > /tmp/verifier_module.log 2>&1
    if [ $? -eq 0 ]; then
        echo "scipy/_lib tests: PASS ($(grep -E '^[0-9]+ (passed|failed)' /tmp/verifier_module.log | tr '\n' ' '))"
    else
        echo "FAIL: project module suite scipy/_lib/tests/test__util.py fails" >&2
        tail -15 /tmp/verifier_module.log >&2
        failures=1
    fi
else
    echo "note: project suites skipped because an earlier check failed" >&2
fi

# ---- 5. hidden cases: same code path, inputs the upstream test never uses --
for case_dir in /tests/hidden/*/; do
    check="$case_dir/check.py"
    [ -f "$check" ] || continue
    name=$(basename "$case_dir")
    if python3 "$check" > /tmp/verifier_hidden.log 2>&1; then
        echo "hidden $name: PASS"
    else
        echo "FAIL: hidden case $name failed" >&2
        tail -8 /tmp/verifier_hidden.log >&2
        failures=1
    fi
done

# ---- reward -----------------------------------------------------------------
if [ $failures -eq 0 ]; then
    echo "VERIFIER: all checks passed, reward=1"
    echo 1 > /logs/verifier/reward.txt
else
    echo "VERIFIER: failures present, reward=0" >&2
    echo 0 > /logs/verifier/reward.txt
fi
exit 0