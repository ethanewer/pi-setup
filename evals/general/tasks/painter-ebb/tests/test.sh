#!/bin/bash
# Verifier for painter-ebb: a SWE-bench-shaped debugging task on the real
# python/mypy tree. The agent must write its own failing reproduction
# (/app/repro.py), repair the Type[T]-with-union-bound constructor bug in
# /app/src, and write /app/diagnosis.md.
#
# Checks, in order:
#   0. provenance: /app/src is the real mypy tree at the buggy revision
#      (markers present, .git absent), the pristine pre-fix copy at
#      /opt/pristine-src is untampered, the golden regression files at
#      /opt/golden match the upstream fix commit byte-for-byte, the test
#      runner modules, the pytest configuration surface (pyproject.toml,
#      conftest.py, tox.ini) and the one non-overlaid data file in the
#      agent's tree match the pristine parent hashes, no sitecustomize.py
#      shim was planted, and mypy/checkexpr.py was actually modified,
#   1. /app/repro.py exists and, run against the pristine tree, still fails
#      with the bug's signature ("Incompatible return value type"), and runs
#      clean (exit 0) against the repaired tree,
#   2. /app/diagnosis.md identifies the real module and the ret-type cause,
#   3. the project's own pytest suite is run against the repaired tree from
#      an isolated sandbox directory OUTSIDE /app, with the test runner
#      copied from the pristine tree and the fix commit's own regression data
#      overlaid (read-only): the golden case
#      testTypeUsingTypeCConstructorReturnFromTypeVarUnionBound, the whole
#      testTypeUsingTypeC family (26 pre-existing cases: nothing else broke),
#      the match-arm case testMatchTypeObjectTypeVar (upstream updated this
#      case's expected reveal when fixing the bug: extra behavioral gate) and
#      the PEP 695 case testPEP695UpperBoundTypeTypeConstructorReturnType.
#      Running pytest from the sandbox (rootdir outside /app, runner outside
#      /app, data files read-only) neutralizes any ability to hijack the
#      suite through the agent's own tree: edits to pyproject.toml addopts
#      (e.g. --update-data), a force-pass conftest.py, or poisoned data
#      files. The checked data files are hash-verified again after each gate.
#   4. every hidden case: must fail on the pristine tree with the bug's
#      signature and type-check cleanly on the repaired tree.
# Reward is written on every exit path and is strictly a 0 or a 1.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
# No user site-packages: a planted usercustomize.py must not hijack the
# verifier's python interpreters. No inherited pytest addopts either.
export PYTHONNOUSERSITE=1
export PYTEST_ADDOPTS=
mkdir -p /logs/verifier
failures=0

echo "== painter-ebb verifier =="

# hashes computed from the pinned upstream revision cd75c4ec... and the fix
# commit 4c8f9944... (see environment/Dockerfile)
PARENT_CHECKEXPR="81649af93b6f725cf6958e661ab79b752d601720564f7d7407f062e3a5dba12d"
PARENT_TESTCHECK="d691cdae8f533279a2a7e7348e33ddec4aa7f796f3ab9ffaa96503ef5fad1a5a"
PARENT_DATA="91d09c45fec49b8cb65aa0398d782bebf4854b8dc66b51b96307b6fe7ad77087"
PARENT_HELPERS="db21587c5ae1f88bc6109fc293a71d572d112ca3c1e28ea9789bee4a6514c45c"
PARENT_CONFIG="54478fbf3ec11d670d0904b5a98e47fac3af0a036e20ddb263acd99976e8f645"
PARENT_TYPEFIXTURE="faa583af95b197c8d446dacc57078304dbac504b896f49d6839af88b0c205f8d"
PARENT_README="5b404b806a7be9844b7e17e6e7e4622811c2a6a6f3987c45444a9c4ddd3925a7"
PARENT_NAMEDTUPLE_TEST="848b329bd1434c4cd03fe273e783edeaa31be9a76508b1839b900755f74c55f2"
# pytest configuration surface of the agent tree: must stay pristine so the
# suite cannot be steered through addopts/conftest hijacking (dead code in
# the sandbox runs, but a planted change is itself a red flag).
PARENT_CONFTEST="485dc4af82de9c56e0e15713565dbca993f88d964b8a14c61ea30ee1739bc079"
PARENT_PYPROJECT="e936a589febebaa14605d361a50ed91f186db2d30a660f60bb22d387475efddb"
PARENT_TOX="f466ab95ae89e3027f9a7b8beebc806adde9aa2c68f372329f4dbd9720601ed1"
# Combined digest of every file under mypy/test: the whole import-time
# surface of the test runner (including mypy/test/__init__.py) must stay
# pristine, so a planted module cannot execute inside the verifier's pytest.
PARENT_MYPY_TEST="c0071b236afbeabad5d989a0b44fd733195cc05c5b5e2e691d4607ac232ebe39"
GOLD_CLASSES="e860151ba14bbb4d692d25493fcb856704a1c87c12803778fd2c9b9f8151f9a1"
GOLD_PY310="7ca5f5f7877f6ae00da84ad30b857c6c5ea9951a2efe76dec38a63ceffa2c41b"
GOLD_PY312="4a1fb06ec3ff497cca995d6361d5b47041704fb04f2652917c5bfe14d0ef2904"

sha() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

dir_digest() {
    # $1 = directory; sha256 over sorted "relpath:filehash" lines, so any
    # added, removed or modified file changes the digest.
    python3 -c '
import hashlib, os, sys
root = sys.argv[1]
h = hashlib.sha256()
for dirpath, dirs, files in os.walk(root):
    dirs.sort()
    for f in sorted(files):
        p = os.path.join(dirpath, f)
        with open(p, "rb") as fh:
            h.update(hashlib.sha256(fh.read()).hexdigest().encode())
        h.update(b" ")
        h.update(os.path.relpath(p, root).encode())
        h.update(b"\n")
print(h.hexdigest())
' "$1";
}

check_hash() {
    # $1 = path, $2 = expected hash, $3 = description
    if [ ! -f "$1" ]; then
        echo "FAIL: $3 missing at $1" >&2
        return 1
    fi
    local got
    got=$(sha "$1")
    if [ "$got" != "$2" ]; then
        echo "FAIL: $3 at $1 has unexpected content (sha256 $got)" >&2
        return 1
    fi
    return 0
}

# ---- 0. provenance ----------------------------------------------------------
[ -f /app/src/mypy/checkexpr.py ] || { echo "FAIL: /app/src is not the mypy source tree" >&2; failures=1; }
[ -f /app/src/mypy/test/testcheck.py ] || { echo "FAIL: /app/src is not the mypy source tree (test runner absent)" >&2; failures=1; }
[ -f /app/src/test-data/unit/check-classes.test ] || { echo "FAIL: /app/src is not the mypy source tree (test data absent)" >&2; failures=1; }
if [ -d /app/src/.git ]; then
    echo "FAIL: git metadata present in /app/src: the tree must stay a plain checkout" >&2
    failures=1
fi
if [ -f /app/src/sitecustomize.py ]; then
    echo "FAIL: /app/src/sitecustomize.py present: a planted interpreter shim is not a repair" >&2
    failures=1
fi

if [ ! -f /opt/pristine-src/mypy/checkexpr.py ] || [ ! -d /opt/pristine-src/test-data/unit ]; then
    echo "FAIL: pristine pre-fix tree /opt/pristine-src missing" >&2
    failures=1
fi
check_hash /opt/pristine-src/mypy/checkexpr.py "$PARENT_CHECKEXPR" "pristine checkexpr.py (must be the buggy parent revision)" || failures=1
check_hash /opt/pristine-src/mypy/test/testcheck.py "$PARENT_TESTCHECK" "pristine testcheck.py" || failures=1
check_hash /opt/pristine-src/README.md "$PARENT_README" "pristine README.md" || failures=1

check_hash /opt/golden/check-classes.test "$GOLD_CLASSES" "golden check-classes.test (fix-commit regression data)" || failures=1
check_hash /opt/golden/check-python310.test "$GOLD_PY310" "golden check-python310.test (fix-commit data)" || failures=1
check_hash /opt/golden/check-python312.test "$GOLD_PY312" "golden check-python312.test (fix-commit data)" || failures=1

# The agent must not have touched the test machinery, the pytest config
# surface, or the data file the gates do not overlay.
check_hash /app/src/mypy/test/testcheck.py "$PARENT_TESTCHECK" "test runner testcheck.py (must stay pristine)" || failures=1
check_hash /app/src/mypy/test/data.py "$PARENT_DATA" "test data.py (must stay pristine)" || failures=1
check_hash /app/src/mypy/test/helpers.py "$PARENT_HELPERS" "test helpers.py (must stay pristine)" || failures=1
check_hash /app/src/mypy/test/config.py "$PARENT_CONFIG" "test config.py (must stay pristine)" || failures=1
check_hash /app/src/mypy/test/typefixture.py "$PARENT_TYPEFIXTURE" "test typefixture.py (must stay pristine)" || failures=1
check_hash /app/src/test-data/unit/check-class-namedtuple.test "$PARENT_NAMEDTUPLE_TEST" "check-class-namedtuple.test (must stay pristine)" || failures=1
check_hash /app/src/pyproject.toml "$PARENT_PYPROJECT" "pyproject.toml (pytest config must stay pristine)" || failures=1
if [ "$(dir_digest /app/src/mypy/test)" != "$PARENT_MYPY_TEST" ]; then
    echo "FAIL: the mypy/test/ directory in /app/src is not pristine (a planted running module cannot be part of a repair)" >&2
    failures=1
fi
check_hash /app/src/conftest.py "$PARENT_CONFTEST" "conftest.py (pytest hooks must stay pristine)" || failures=1
check_hash /app/src/tox.ini "$PARENT_TOX" "tox.ini (pytest config must stay pristine)" || failures=1

if [ "$(sha /app/src/mypy/checkexpr.py)" = "$PARENT_CHECKEXPR" ]; then
    echo "FAIL: /app/src/mypy/checkexpr.py was not modified at all; no repair happened" >&2
    failures=1
else
    echo "provenance: real tree, no .git, runner/data/config pristine, checkexpr.py modified"
fi

# ---- 1. /app/repro.py in both directions -----------------------------------
if [ ! -f /app/repro.py ]; then
    echo "FAIL: deliverable /app/repro.py missing" >&2
    failures=1
else
    # pre-fix half: the bug must reproduce on the pristine tree
    out=$(cd /opt/pristine-src && python3 -m mypy --no-incremental --cache-dir=/tmp/myc_pristine /app/repro.py 2>&1)
    rc=$?
    if [ $rc -eq 0 ]; then
        echo "FAIL: /app/repro.py does not reproduce the bug on the pristine tree (mypy exited 0)" >&2
        failures=1
    elif ! printf '%s' "$out" | grep -q "Incompatible return value type"; then
        echo "FAIL: /app/repro.py fails on the pristine tree but not with the bug's signature:" >&2
        printf '%s\n' "$out" | tail -5 >&2
        failures=1
    else
        echo "repro pre-fix: FAILS on pristine tree with the bug's error (PASS)"
    fi
    # repaired half: the repro must type-check cleanly on /app/src
    out=$(cd /app/src && python3 -m mypy --no-incremental --cache-dir=/tmp/myc_repaired /app/repro.py 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "FAIL: /app/repro.py still fails on the repaired tree:" >&2
        printf '%s\n' "$out" | tail -8 >&2
        failures=1
    elif printf '%s' "$out" | grep -q "error:"; then
        echo "FAIL: /app/repro.py on the repaired tree reported errors despite exit 0:" >&2
        printf '%s\n' "$out" | tail -8 >&2
        failures=1
    else
        echo "repro repaired: PASSES on the repaired tree (PASS)"
    fi
fi

# ---- 2. /app/diagnosis.md ---------------------------------------------------
if [ ! -f /app/diagnosis.md ]; then
    echo "FAIL: deliverable /app/diagnosis.md missing" >&2
    failures=1
else
    python3 - /app/diagnosis.md <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
low = text.lower()
ok = (len(text.strip()) >= 120
      and "checkexpr" in low
      and ("ret_type" in low or "return type" in low or "return types" in low)
      and ("union" in low))
if not ok:
    print("FAIL: /app/diagnosis.md does not identify the real module and the "
          f"ret-type/union cause (len={len(text.strip())}, mentions "
          f"checkexpr={'checkexpr' in low}, ret-type="
          f"{'ret_type' in low or 'return type' in low or 'return types' in low}, "
          f"union={'union' in low})", file=sys.stderr)
    sys.exit(1)
print("diagnosis: acceptable (names module + ret-type/union cause)")
PY
    rc=$?
    if [ $rc -ne 0 ]; then
        failures=1
    fi
fi

# ---- 3. the project's own suite against the repaired tree -------------------
# Sandbox: the suite is executed from outside /app with the pristine test
# runner and read-only, fix-commit regression data, so the agent's tree
# cannot steer pytest (no pyproject addopts, no conftest hooks, no
# --update-data rewrite of expectations). The code under test - the mypy
# package - still comes from /app/src via PYTHONPATH.
SANDBOX=/tmp/mypy-verify-sandbox
if [ $failures -eq 0 ]; then
    rm -rf "$SANDBOX"
    mkdir -p "$SANDBOX"
    cp -a /opt/pristine-src/mypy/test "$SANDBOX/mypy-test"
    chmod -R u+w "$SANDBOX/mypy-test"
    cp -a /opt/pristine-src/test-data "$SANDBOX/test-data"
    cp /opt/golden/check-classes.test "$SANDBOX/test-data/unit/check-classes.test"
    cp /opt/golden/check-python310.test "$SANDBOX/test-data/unit/check-python310.test"
    cp /opt/golden/check-python312.test "$SANDBOX/test-data/unit/check-python312.test"
    # The expected outputs are fixed: the four gates must match them, so the
    # data files are read-only against any attempt to rewrite expectations.
    chmod -R a-w "$SANDBOX/test-data"

    run_gate() {
        # $1 = gate name, $2 = -k expression, $3 = log file
        (cd "$SANDBOX" && PYTHONPATH=/app/src MYPY_TEST_PREFIX="$SANDBOX" \
            python3 -m pytest -p mypy.test.data -p no:cacheprovider \
            --color=no --rootdir="$SANDBOX" mypy-test/testcheck.py -q -k "$2") > "$3" 2>&1
    }

    # 3a. the golden regression case, by its upstream name
    run_gate golden testTypeUsingTypeCConstructorReturnFromTypeVarUnionBound /tmp/verifier_golden.log
    rc=$?
    if [ $rc -eq 0 ] && grep -q "passed" /tmp/verifier_golden.log; then
        echo "golden regression test testTypeUsingTypeCConstructorReturnFromTypeVarUnionBound: PASS"
    else
        echo "FAIL: golden regression test failed" >&2
        tail -15 /tmp/verifier_golden.log >&2
        failures=1
    fi

    # 3b. the pre-existing testTypeUsingTypeC family (26 cases) - the fix
    # must not have broken any of them
    run_gate family 'testTypeUsingTypeC and not testTypeUsingTypeCConstructorReturnFromTypeVarUnionBound' /tmp/verifier_family.log
    rc=$?
    if [ $rc -eq 0 ] && grep -q "passed" /tmp/verifier_family.log; then
        echo "existing family testTypeUsingTypeC* (pre-fix): PASS"
    else
        echo "FAIL: existing testTypeUsingTypeC* family does not pass on the repaired tree" >&2
        tail -15 /tmp/verifier_family.log >&2
        failures=1
    fi

    # 3c. the match-arm case whose expected reveal the upstream fix changed
    run_gate match testMatchTypeObjectTypeVar /tmp/verifier_match.log
    rc=$?
    if [ $rc -eq 0 ] && grep -q "passed" /tmp/verifier_match.log; then
        echo "match-arm gate testMatchTypeObjectTypeVar: PASS"
    else
        echo "FAIL: match-arm gate testMatchTypeObjectTypeVar failed (reveal must be the" >&2
        echo "      TypeVar instance, not the union)" >&2
        tail -15 /tmp/verifier_match.log >&2
        failures=1
    fi

    # 3d. the PEP 695 'type[T]' variant added by the fix
    run_gate pep695 testPEP695UpperBoundTypeTypeConstructorReturnType /tmp/verifier_pep695.log
    rc=$?
    if [ $rc -eq 0 ] && grep -q "passed" /tmp/verifier_pep695.log; then
        echo "PEP 695 gate testPEP695UpperBoundTypeTypeConstructorReturnType: PASS"
    else
        echo "FAIL: PEP 695 gate testPEP695UpperBoundTypeTypeConstructorReturnType failed" >&2
        tail -15 /tmp/verifier_pep695.log >&2
        failures=1
    fi

    # The gates must not have mutated the expectations: the checked data
    # files are byte-identical to the fix commit's copies after the runs.
    check_hash "$SANDBOX/test-data/unit/check-classes.test" "$GOLD_CLASSES" "post-run check-classes.test (must still match the fix commit)" || failures=1
    check_hash "$SANDBOX/test-data/unit/check-python310.test" "$GOLD_PY310" "post-run check-python310.test (must still match the fix commit)" || failures=1
    check_hash "$SANDBOX/test-data/unit/check-python312.test" "$GOLD_PY312" "post-run check-python312.test (must still match the fix commit)" || failures=1
else
    echo "note: project suite skipped because earlier checks failed" >&2
fi

# ---- 4. hidden cases, both directions ---------------------------------------
for case_dir in /tests/hidden/*/; do
    [ -f "$case_dir/case.py" ] || continue
    name=$(basename "$case_dir")
    # pre-fix half: must reproduce the bug on the pristine tree
    out=$(cd /opt/pristine-src && python3 -m mypy --no-incremental --cache-dir=/tmp/myc_hidden_p "$case_dir/case.py" 2>&1)
    rc=$?
    if [ $rc -eq 0 ]; then
        echo "FAIL: hidden case $name passes on the pristine tree (does not exercise the bug)" >&2
        failures=1
        continue
    fi
    if ! printf '%s' "$out" | grep -q "Incompatible return value type"; then
        echo "FAIL: hidden case $name fails on pristine tree without the bug's signature:" >&2
        printf '%s\n' "$out" | tail -5 >&2
        failures=1
        continue
    fi
    # repaired half: must type-check cleanly
    out=$(cd /app/src && python3 -m mypy --no-incremental --cache-dir=/tmp/myc_hidden_r "$case_dir/case.py" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "FAIL: hidden case $name still fails on the repaired tree:" >&2
        printf '%s\n' "$out" | tail -8 >&2
        failures=1
    elif printf '%s' "$out" | grep -q "error:"; then
        echo "FAIL: hidden case $name reported errors on the repaired tree despite exit 0:" >&2
        printf '%s\n' "$out" | tail -8 >&2
        failures=1
    else
        echo "hidden $name: fails pre-fix with the bug's error, passes post-fix (PASS)"
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