#!/bin/bash
# Verifier for clew-bulkhead: proves the agent's fix in the real scipy/scipy
# tree at /app/src. The trial container has no network; everything executed
# below comes from baked image layers. Steps:
#  0) integrity anchors: sha256-pinned golden regression test (/opt/golden),
#     pre-fix snapshot (/opt/prefix-pylib) and toolchain (/opt/pins);
#  1) provenance: HEAD is still the pinned parent commit; the upstream fix
#     commit is NOT reachable from this clone;
#  2) scope: every tracked file except scipy/spatial/_qhull.pyx is
#     byte-identical to the parent commit; no stray untracked files;
#  3) deliverables: /app/repro.sh (executable) and /app/summary.md exist;
#  4) FORCED regeneration: the compiled _qhull module and its generated C
#     are deleted from the build dir, then the editable install is rebuilt,
#     so the executed module is provably regenerated from the delivered
#     tree's _qhull.pyx (a planted .so or a hand-edited generated .c cannot
#     survive);
#  5) the agent's own reproduction, both directions: must pass on the
#     repaired tree and must FAIL against the pristine pre-fix snapshot
#     (with a real import, not an ImportError);
#  6) the upstream regression test for this bug (extracted from the fix
#     commit at image build time; never part of this task tree) is planted
#     over the tree's copy of test_qhull.py and must pass, together with the
#     project's whole existing geometry test file;
#  7) authored hidden cases hitting the same constructor from inputs the
#     upstream test does not use (0-D scalar, 4-D block) plus a valid
#     2-D-shaped case that must still produce the correct hull.
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

PARENT=4fe05c739b70795b595e1aee3bed87068463123f
FIX=d42bc45c3ffecb0f76398b3f23eeba78a2dc13ac
QSO=/work/sci-build/scipy/spatial/_qhull.cpython-312-x86_64-linux-gnu.so
QPDIR=/work/sci-build/scipy/spatial/_qhull.cpython-312-x86_64-linux-gnu.so.p

# 0) integrity anchors.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/prefix.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden, pre-fix snapshot or toolchain integrity check failed (substituted file)"
fi

# 1) provenance.
cd /app/src || fail "/app/src is missing"
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# 2) scope: only the single source file the bug lives in may differ. Every
#    other tracked file's bytes must equal the pinned commit's own blob
#    (assume-unchanged / skip-worktree invisible), and any untracked
#    non-ignored file is refused.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        scipy/spatial/_qhull.pyx) : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            idx=$(git ls-files -s -- "$f" | awk '{print $2}')
            mode=$(git ls-files -s -- "$f" | awk '{print $1}')
            if [ "$idx" != "$want" ]; then
                echo "index oid mismatch for tracked file: $f" >> "$LOG"; ok=0; continue
            fi
            case "$mode" in
                160000*) : ;; # submodule gitlink; dir contents sit in their own repo
                120000*)
                    have=$(readlink "$f" 2>/dev/null || true)
                    want2=$(git cat-file blob "$want" 2>/dev/null || true)
                    if [ "$have" != "$want2" ]; then
                        echo "worktree differs from parent for symlink: $f" >> "$LOG"; ok=0
                    fi
                    ;;
                *)
                    # Byte-exact comparison of the worktree file against the
                    # pinned commit's own blob, immune to git's stat cache and
                    # to hash-object's EOL normalization of committed CR bytes.
                    if ! git cat-file blob "$want" 2>/dev/null | cmp -s - "$f"; then
                        echo "worktree differs from parent for tracked file: $f" >> "$LOG"; ok=0
                    fi
                    ;;
            esac
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

# 3) deliverables.
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) forced regeneration from the tree the agent delivered. Deleting the
#    compiled module AND its generated C source forces cython + the C
#    compiler to rebuild _qhull from the delivered _qhull.pyx, so the code
#    executed below provably comes from the agent's own source, and a tree
#    that no longer compiles fails here.
rm -f "$QSO" "$QPDIR/_qhull.c" || fail "cannot remove build dir artifacts"
if ! ( cd /app/src && python3 -m pip install -e . --no-build-isolation \
        --config-settings=builddir=/work/sci-build ) > "$LOG.rebuild" 2>&1; then
    tail -30 "$LOG.rebuild" >&2
    fail "incremental rebuild failed on the agent's tree (see $LOG.rebuild)"
fi
[ -f "$QSO" ] || fail "_qhull module not produced by the rebuild"
if ! ( cd /tmp && python3 -c "from scipy.spatial import ConvexHull" >/dev/null 2>&1 ); then
    fail "scipy.spatial does not import after the rebuild"
fi

# 5) the agent's reproduction, both directions. On the repaired tree it must
#    exit 0; against the pristine pre-fix snapshot it must exit non-zero,
#    and the failure must come from running the real pre-fix scipy (not an
#    ImportError from a broken environment).
if ! bash /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
if MESONPY_EDITABLE_SKIP=/work/sci-build \
        PYTHONPATH=/opt/prefix-pylib/usr/local/lib/python3.12/site-packages \
        bash /app/repro.sh > /tmp/repro_prefix.out 2>&1; then
    echo "agent repro passed against the PRE-FIX snapshot (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi
if grep -qiE 'import error|no module named' /tmp/repro_prefix.out; then
    echo "pre-fix run failed with an import error, not the bug; output:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "pre-fix repro run did not exercise the real pre-fix scipy (see $LOG)"
fi

# 6) plant the upstream regression test (golden bytes from the fix commit,
#    sha256-pinned; the whole test_qhull.py file from the fix commit, which
#    is the parent file plus this one test) over the tree's copy, then run
#    the project's own test runner on the whole file.
cp /opt/golden/test_qhull.py scipy/spatial/tests/test_qhull.py \
    || fail "cannot plant golden test_qhull.py"
if ! ( cd /tmp && python3 -m pytest /app/src/scipy/spatial/tests/test_qhull.py \
        -k "points_wrong_dim_fails" -q ) > "$LOG.golden" 2>&1; then
    tail -25 "$LOG.golden" >&2
    fail "upstream regression test did not pass (see $LOG.golden)"
fi
grep -qE "2 passed" "$LOG.golden" || {
    tail -15 "$LOG.golden" >&2
    fail "points_wrong_dim_fails did not run both parametrizations (see $LOG.golden)"
}
if ! ( cd /tmp && python3 -m pytest /app/src/scipy/spatial/tests/test_qhull.py -q ) \
        > "$LOG.full" 2>&1; then
    tail -30 "$LOG.full" >&2
    fail "full test_qhull.py did not pass on the fixed tree (see $LOG.full)"
fi
grep -qE "192 passed" "$LOG.full" || {
    tail -10 "$LOG.full" >&2
    fail "test_qhull.py did not report 192 passed (see $LOG.full)"
}

# 7) authored hidden cases: same constructor, inputs the upstream test does
#    not use (0-D scalar, 4-D block, valid 2-D-shaped cloud), each must exit 0.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    ( cd "$work" && bash run.sh > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: exited $rc (expected 0); stderr:" >> "$LOG"
        head -15 "$work/stderr.txt" >> "$LOG"
        head -15 "$work/stdout.txt" >> "$LOG"
        fail "hidden case $name: exited $rc (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected 3"

echo "PASS: provenance, fix-unreachable, scope, deliverables, forced regeneration, repro both directions, upstream regression test, full geometry suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0