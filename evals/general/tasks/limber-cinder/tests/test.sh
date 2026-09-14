#!/bin/bash
# Verifier for limber-cinder: proves the agent's fix in the real
# pallets/jinja tree at /app/src by (1) asserting the verifier's own trust
# anchors (the sha256 pins of the golden regression test, the pristine
# pre-fix package manifest and the Python/pytest toolchain), (2) asserting
# provenance (HEAD still the pinned parent commit; the upstream fix commit
# is not reachable from this clone; every tracked file except the single
# source file the bug lives in is byte-identical to the parent commit; no
# untracked non-ignored files), (3) requiring /app/repro.py and
# /app/summary.md, (4) requiring `import jinja2` to resolve to
# /app/src/src (the repaired editable tree), (5) running the agent's own
# reproduction against the repaired tree (must pass and print False) and
# against the pristine pre-fix package bake at /opt/pre-fix-jinja under
# PYTHONPATH (must fail - proves the symptom is real and the reproduction
# targets it), (6) planting the project's own regression test for this bug
# (the fix commit's tests/test_api.py, extracted at image build time into
# /opt/golden and sha256-pinned) over the tree's copy and requiring
# test_default_undefined and test_strict_undefined to pass, (7) running the
# previously-existing suite (18 green test files; test_debug.py and
# test_loader.py excluded for unrelated era issues) and (8) running four
# authored hidden cases that reach the same membership-on-undefined code
# path from inputs the upstream regression test does not use.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=189132094135d4c84414404c3b388500d35dc49e
FIX=d5f49f5cc135f1a78704dba7db8212be2388b50e

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the tree, the golden test, the
#    pristine pre-fix package and (via pytest and python3) the toolchain; an
#    adversarial agent with write access to /opt or /usr could otherwise
#    replace /opt/pre-fix-jinja with code that reproduces no bug (so the
#    pre-fix direction check fails to fail), tamper with the golden test, or
#    stub the interpreter. The pins recorded at image build time detect any
#    substitution before anything is executed. The site-packages state is
#    pinned too (names AND hashes), because a startup hook
#    (sitecustomize/usercustomize) planted there would run in every
#    interpreter of every check below and could make everything pass while
#    the tree stays unfixed; the agent runs as root in this container, so
#    the writable surface is the whole image.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/pre-fix-manifest.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden, pre-fix copy or toolchain integrity check failed (substituted file)"
fi
# site-packages must be byte-identical AND contain exactly the build-time
# file set (a diff against the pinned manifest catches added files, which
# sha256sum -c alone would not).
SP_TMP=$(mktemp)
find /usr/local/lib/python3.12/site-packages -type f ! -path "*/__pycache__/*" -print0 2>/dev/null | sort -z | xargs -0 sha256sum > "$SP_TMP" 2>/dev/null
if ! diff -q "$SP_TMP" /opt/pins/site-packages.sha256 >/dev/null 2>&1; then
    rm -f "$SP_TMP"
    fail "site-packages differs from the pinned build-time state (substituted or added file)"
fi
rm -f "$SP_TMP"
# No auto-imported startup hook may exist, and the user site must stay
# absent (a root agent could create one to run code on every interpreter
# start without touching the tree).
if python3 -c "import sitecustomize" >/dev/null 2>&1; then
    fail "sitecustomize startup hook present (fix wrapped outside the tree)"
fi
if python3 -c "import usercustomize" >/dev/null 2>&1; then
    fail "usercustomize startup hook present (fix wrapped outside the tree)"
fi
if [ -e /root/.local ]; then
    fail "user site /root/.local created (startup hook injection vector)"
fi

# 1) provenance: the tree must still be at the pinned parent commit (no
#    commits added) and the upstream fix commit must not be reachable from
#    this object store (an agent that fetched or grafted the fix earns 0;
#    the fix direction must come from the agent's own work).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# 2) scope: every change must live in exactly the one source file the bug
#    lives in (in the runtime, discovered by the agent, not named here).
#    This is a CONTENT check, not a git-status check: the actual bytes of
#    every tracked file on disk are hashed against the pinned commit's own
#    blob, so assume-unchanged / skip-worktree tricks cannot hide a dirty
#    file, and any untracked non-ignored file is refused.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        src/jinja2/runtime.py) : ;;  # the one source file the bug lives in
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            idx=$(git ls-files -s -- "$f" | awk '{print $2}')
            if [ "$idx" != "$want" ]; then
                echo "index oid mismatch for tracked file: $f" >> "$LOG"; ok=0; continue
            fi
            have=$(git hash-object -- "$f" 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "worktree differs from parent for tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 2b) the bug's source file must actually have been changed in the tree.
#    (With the scope check above, an honest fix of this defect has exactly
#    one place it can live, so a pristine source file proves the behaviour
#    was never repaired in the shipped tree.)
if [ "$(git hash-object -- src/jinja2/runtime.py)" = "$(git rev-parse "$PARENT:src/jinja2/runtime.py")" ]; then
    fail "src/jinja2/runtime.py is byte-identical to the parent commit - the shipped tree was never repaired"
fi
# 2c) the fix must be encoded in the TREE's own source, not just shadowed
#    at runtime: the buggy alias line (Undefined.__contains__ wired to the
#    fail-op) must be gone from the shipped file. A correct fix - however
#    written - necessarily removes it; a tree that still contains it is an
#    unfixed tree.
if grep -q '__call__ = __getitem__ = __contains__ = _fail_with_undefined_error' src/jinja2/runtime.py; then
    fail "src/jinja2/runtime.py still wires Undefined.__contains__ to _fail_with_undefined_error (buggy alias present, fix not in the tree)"
fi

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -s /app/repro.py ] || fail "/app/repro.py is missing or empty"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) the interpreter must be importing the REPAIRED TREE, not a redirected
#    copy of the package.
if ! python3 -c "import jinja2; assert jinja2.__file__.startswith('/app/src/src'), jinja2.__file__" > /tmp/import.out 2>&1; then
    head -10 /tmp/import.out >> "$LOG"
    fail "import jinja2 does not resolve to /app/src/src (editable install broken or redirected)"
fi

# 5) the agent's reproduction, both directions. Against the repaired tree
#    it must pass - exit 0 AND print False. Against the pristine pre-fix
#    package baked into the image it must fail - any exit 0 there means the
#    reproduction is fake/hardcoded or the symptom is not what we think it
#    is.
if ! python3 /app/repro.py > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
if ! grep -q "False" /tmp/repro_fixed.out; then
    echo "agent repro did not print the rendered 'False'; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro did not render/print False on the repaired tree (see $LOG)"
fi
PYTHONPATH=/opt/pre-fix-jinja python3 /app/repro.py > /tmp/repro_prefix.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "agent repro passed against the PRE-FIX copy (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix copy (see $LOG)"
fi

# 6) plant the upstream regression test (golden bytes, extracted from the
#    fix commit at image build time and sha256-pinned; never part of this
#    task tree) over the tree's copy of tests/test_api.py, then run the two
#    regression tests: the default-undefined membership assertion and the
#    strict-undefined must-still-raise assertion.
cp /opt/golden/test_api.py tests/test_api.py \
    || fail "cannot plant golden test_api.py"
if [ "$(sha256sum tests/test_api.py | awk '{print $1}')" != "$(awk '{print $1}' /opt/pins/golden.sha256)" ]; then
    fail "planted test_api.py does not match the pinned golden bytes"
fi
if ! python3 -m pytest tests/test_api.py::TestUndefined::test_default_undefined \
     tests/test_api.py::TestUndefined::test_strict_undefined \
     -q -p no:cacheprovider > "$LOG.golden" 2>&1; then
    tail -25 "$LOG.golden" >&2
    fail "golden regression tests did not pass (see $LOG.golden)"
fi
grep -q "2 passed" "$LOG.golden" || {
    tail -15 "$LOG.golden" >&2
    fail "golden tests did not report 2 passed (see $LOG.golden)"
}

# 7) previously-existing test files must stay green. The scope check above
#    guarantees these files are byte-identical to the pinned commit (the
#    agent never touched them), so a green run proves the fix broke nothing
#    else. tests/test_debug.py and tests/test_loader.py are excluded: at
#    this development-era snapshot they fail in this environment for
#    unrelated reasons (old traceback format / removed pytest module
#    teardown API).
SUITE="tests/test_api.py tests/test_async.py tests/test_async_filters.py tests/test_bytecode_cache.py tests/test_compile.py tests/test_core_tags.py tests/test_features.py tests/test_filters.py tests/test_idtracking.py tests/test_imports.py tests/test_inheritance.py tests/test_lexnparse.py tests/test_nativetypes.py tests/test_regression.py tests/test_runtime.py tests/test_security.py tests/test_tests.py tests/test_utils.py"
if ! python3 -m pytest $SUITE -q -p no:cacheprovider > "$LOG.suite" 2>&1; then
    tail -30 "$LOG.suite" >&2
    fail "existing suite not green on the repaired tree (see $LOG.suite)"
fi
grep -q "732 passed" "$LOG.suite" || {
    tail -15 "$LOG.suite" >&2
    fail "suite did not report 732 passed (see $LOG.suite)"
}

# 8) four authored hidden cases reach the same membership-on-undefined code
#    path from inputs the upstream regression test does not use: not-in and
#    conditional forms, chainable undefined, numeric key / missing
#    attribute on a real object / debug undefined, and strict-undefined
#    still raising. Each must exit 0.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    ( cd "$work" && bash run.sh > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: exited $rc (expected 0); stdout/stderr:" >> "$LOG"
        head -15 "$work/stdout.txt" >> "$LOG"
        head -15 "$work/stderr.txt" >> "$LOG"
        fail "hidden case $name: exited $rc (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 4 ] || fail "only $CASES hidden case(s) ran; expected 4"

echo "PASS: provenance, fix-unreachable, scope, deliverables, import provenance, repro both directions, upstream regression tests, existing suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0