#!/bin/bash
# Verifier for wherry-trim: proves the agent's fix in the real scikit-image
# tree at /app/src by (1) asserting the verifier's own trust anchors (the
# golden regression test file and the pristine pre-fix fit.py still have the
# sha256 pins recorded at image build time, as does the interpreter/editable
# loader), (2) asserting provenance (HEAD still the pinned parent commit; the
# upstream fix commit is not reachable from this clone; the object store holds
# exactly one commit; every tracked file except the single source file the bug
# lives in is byte-identical to the parent commit; no stray untracked files),
# (3) requiring the /app/repro.py and /app/summary.md deliverables, (4)
# running the agent's own reproduction against a PRISTINE pre-fix copy of the
# whole package baked at /opt/prefix (must FAIL - proves the symptom is real
# and the reproduction targets it) and against the agent's repaired tree (must
# PASS), (5) planting the upstream project's own regression test (test_fit.py
# extracted from the fix commit at image build time into /opt/golden,
# sha256-pinned) and running the full test_fit.py module against the repaired
# tree, and (6) running two authored hidden cases that exercise the same
# budget computation from inputs the upstream test does not use, each in BOTH
# the pristine direction (must fail) and the repaired direction (must pass).
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

PARENT=f1892afb76e60b6fe41cf0c73be97f918581aa33
FIX=137dbfb5f1e597cf4cb069486319d7defdd1077e
SITE=/usr/local/lib/python3.12/site-packages

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the tree, the golden test and
#    (through the package) the interpreter; an adversarial root agent could
#    otherwise replace the golden test, the pristine pre-fix fit.py, the
#    interpreter, or the editable loader with a stub that fakes a green run.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/prefix-fit.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden, pristine-fit or toolchain integrity check failed (substituted file)"
fi

# 1) provenance: the tree must still be at the pinned parent commit (no
#    commits added) and the upstream fix commit must not be reachable from
#    this object store (an agent that fetched or grafted the fix earns 0).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi
if [ "$(git rev-list --count HEAD)" != "1" ]; then
    fail "object store holds $(git rev-list --count HEAD) commit(s); expected exactly 1"
fi

# 2) scope: every change must live in exactly the one source file the bug
#    lives in (the robust-fitting implementation, discovered by the agent,
#    not named here). This is a CONTENT check: the actual bytes of every
#    tracked file on disk are hashed against the pinned commit's own blob, so
#    assume-unchanged / skip-worktree tricks cannot hide a dirty file, and any
#    untracked non-ignored file is refused.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        skimage/measure/fit.py) : ;;  # the one source file the bug lives in
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            idx=$(git ls-files -s -- "$f" | awk '{print $2}')
            mode=$(git ls-files -s -- "$f" | awk '{print $1}')
            have=
            if [ "$idx" != "$want" ]; then
                echo "index oid mismatch for tracked file: $f" >> "$LOG"; ok=0; continue
            fi
            case "$mode" in
                160000*) : ;;  # gitlink: never materialised by a shallow clone
                120000*)
                    have=$(printf '%s' "$(readlink "$f")" | git hash-object --stdin 2>/dev/null || true)
                    ;;
                *)
                    have=$(git hash-object -- "$f" 2>/dev/null || true)
                    ;;
            esac
            if [ -n "$have" ] && [ "$have" != "$want" ]; then
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

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -s /app/repro.py ] || fail "/app/repro.py is missing or empty"
[ -x /app/repro.py ] || fail "/app/repro.py is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) the agent's reproduction against the PRISTINE PRE-FIX package. The
#    pristine copy of the whole package lives at /opt/prefix (source .py
#    merged with compiled .so, fit.py at the parent blob); python3 -S disables
#    the site machinery so the meson editable meta-finder cannot shadow the
#    copy and PYTHONPATH wins. The reproduction MUST FAIL here: any exit 0
#    means the reproduction is fake/hardcoded or the symptom is not what the
#    verifier believes it is.
cd /tmp || fail "cannot cd /tmp"
if PYTHONPATH=/opt/prefix:$SITE python3 -S /app/repro.py \
        > /tmp/repro_prefix.out 2>&1; then
    echo "agent repro passed against the PRISTINE PRE-FIX package (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix code (see $LOG)"
fi

# 5) the agent's reproduction against the repaired tree: must PASS (exit 0).
if ! python3 /app/repro.py > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi

# 6) plant the upstream regression test (golden bytes, extracted from the fix
#    commit at image build time and sha256-pinned; never part of this task
#    tree) over the tree's copy, then run the WHOLE robust-fitting test module
#    (the project's own suite) plus the golden test by its exact node id.
cd /app/src || fail "cannot cd /app/src"
cp /opt/golden/test_fit.py skimage/measure/tests/test_fit.py \
    || fail "cannot plant golden test_fit.py"
if ! ( cd /app/src && python3 -m pytest skimage/measure/tests/test_fit.py \
        -p no:cacheprovider -q > "$LOG.golden" 2>&1 ); then
    tail -30 "$LOG.golden" >&2
    fail "test_fit.py (with upstream regression test planted) did not pass (see $LOG.golden)"
fi
grep -q "30 passed" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "test_fit.py did not report 30 passed on the repaired tree (see $LOG.golden)"
}
if ! ( cd /app/src && python3 -m pytest \
        "skimage/measure/tests/test_fit.py::test_ransac_dynamic_max_trials_clipping" \
        -p no:cacheprovider -q > "$LOG.goldenone" 2>&1 ); then
    tail -30 "$LOG.goldenone" >&2
    fail "the upstream regression test did not pass on the repaired tree (see $LOG.goldenone)"
fi
grep -q "1 passed" "$LOG.goldenone" || {
    tail -20 "$LOG.goldenone" >&2
    fail "the upstream regression test did not report 1 passed (see $LOG.goldenone)"
}

# 7) two authored hidden cases exercising the same budget computation from
#    inputs the upstream test does not use. Each case runs TWICE: against the
#    pristine pre-fix package (must FAIL - proves the case bites the unfixed
#    code) and against the repaired tree (must PASS).
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    cp "$case"check.py "$work"/check.py || fail "hidden case $name: missing check.py"

    # pristine direction: must fail against the pre-fix package
    ( cd "$work" && SKIMAGE_PRESTINE=1 bash run.sh > stdout-prefix.txt 2> stderr-prefix.txt )
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "hidden case $name: PASSED on the pristine pre-fix package (expected failure); stdout:" >> "$LOG"
        head -10 "$work/stdout-prefix.txt" >> "$LOG"
        fail "hidden case $name did not fail on the pre-fix code (see $LOG)"
    fi

    # repaired direction: must pass against the agent's tree
    ( cd "$work" && bash run.sh > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: exited $rc on the repaired tree (expected 0); stderr:" >> "$LOG"
        head -15 "$work/stderr.txt" >> "$LOG"
        head -15 "$work/stdout.txt" >> "$LOG"
        fail "hidden case $name: exited $rc (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 2 ] || fail "only $CASES hidden case(s) ran; expected 2"

echo "PASS: provenance, fix-unreachable, scope, deliverables, repro fails pre-fix / passes repaired, golden + full module pass, hidden cases bite both directions"
echo 1 > /logs/verifier/reward.txt
exit 0