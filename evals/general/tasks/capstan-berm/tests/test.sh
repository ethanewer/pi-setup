#!/bin/bash
# Verifier for capstan-berm: proves the agent's fix in the real scikit-image
# tree at /app/src by (1) asserting provenance (HEAD still the pinned parent
# commit, every tracked file except the single thinning source file is
# byte-identical to it, no stray untracked files, and the object store holds
# nothing beyond the pinned commit), (2) requiring /app/summary.md, (3)
# re-running the issue's exact reproduction snippet, (4) planting the upstream
# project's own regression test for this bug (test_skeletonize.py as at the fix
# commit, extracted at image build time into /opt/golden, never vendored into
# this task tree) plus three authored hidden test modules that exercise
# boolean inputs the upstream regression test never uses (a non-square comb,
# partial max_num_iter thinning of a disc, and non-contiguous strided/
# reversed/transposed boolean views whose aliased buffers must be preserved),
# and (5) running the project's own pytest on every one of those modules,
# demanding that the whole run passes AND that each required regression/hidden
# test function actually ran and passed.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
# The agent may not smuggle the fix through user-site or PYTHONPATH hooks: every
# graded python process runs with the user site disabled and PYTHONPATH cleared,
# so only the tree itself (/app/src, the editable install) can satisfy the
# functional checks.
export PYTHONNOUSERSITE=1
unset PYTHONPATH
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=6baff20f0fe4c3bee859447f77f0014ec25f820b
FIX=ff3dd9468bd10461363e1f7fdba9b12409fba216
GOLDEN_SHA=5edfb911e066f001e43a8adc284f4a5f8073f102c3cf8417d66ba16bb92bae70

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit (no commits added).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if [ "$(git rev-list HEAD --count)" != "1" ]; then
    fail "clone contains history beyond the pinned parent commit"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (the morphology thinning module, discovered by the agent, not named
#    here). This is a CONTENT check, not a git-status check: we hash the actual
#    bytes of every tracked file on disk against the pinned commit's own blob,
#    so assume-unchanged/skip-worktree tricks cannot hide a dirty file, and we
#    refuse any untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        skimage/morphology/_skeletonize.py) : ;;
        *)
            # submodule gitlinks (mode 160000) are not materialised by the
            # clone and are not files on disk; nothing to compare
            if [ "$(git ls-files -s -- "$f" | awk '{print $1}')" = "160000" ]; then
                :
            else
                want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
                have=$(git hash-object -- "$f" 2>/dev/null || true)
                if [ -z "$have" ] || [ "$have" != "$want" ]; then
                    echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
                fi
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) belt: the object store must hold nothing beyond the pinned parent commit
#    (no sneaked-in upstream commit, no hidden modifications): no unreachable
#    objects, and the fix commit must not be reachable at all.
unreachable=$(git fsck --no-reflogs --unreachable 2>/dev/null | wc -l)
if [ "$unreachable" != "0" ]; then
    fail "object store contains unreachable objects (see fsck)"
fi
if git cat-file -e ${FIX}^{commit} 2>/dev/null; then
    fail "fix commit ${FIX} is reachable from /app/src's object store"
fi

# 4) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
#    deliverable: /app/src must be the live (editable) install, not a stale
#    copy, so the agent's .py edit is what pytest actually imports.
ED=$(cd /app/src && python -c "import skimage.morphology._skeletonize as m; print(m.__file__)" 2>/dev/null)
case "$ED" in
    /app/src/*) : ;;
    *) fail "skimage imports from '$ED', not from /app/src (editable install broken)" ;;
esac
# 4b) belt against a wrapper/hook mask: the LIVE implementation of the graded
#     function must be the tree's own source. A hook that rewrites `thin` at
#     interpreter startup (sitecustomize, user-site, site-packages shim) leaves
#     the buggy tree fully intact while every functional check passes, so we
#     assert that the code object thin resolves to lives under /app/src and
#     that the module and the package attribute are the SAME function (no
#     shadowing). And the grading source file on disk must actually DIFFER from
#     the pinned parent blob -- an untouched tree (bug still present in the
#     graded artifact) is a hard fail whatever the hooks claim.
FNF=$(cd /app/src && python -c "
import skimage.morphology._skeletonize as m
import skimage.morphology as mp
assert m.thin is mp.thin, 'package thin is shadowed by a different object'
print(m.thin.__code__.co_filename)
" 2>/dev/null)
case "$FNF" in
    /app/src/*) : ;;
    *) fail "thin resolves to code at '$FNF', not under /app/src (wrapper/hook detected)" ;;
esac
PB=$(git rev-parse "$PARENT:skimage/morphology/_skeletonize.py")
HB=$(git hash-object -- skimage/morphology/_skeletonize.py)
if [ -z "$HB" ] || [ "$HB" = "$PB" ]; then
    fail "the thinning source file on disk is byte-identical to the pinned parent blob; the bug is still present in the tree"
fi

# 5) plant the upstream regression test (golden bytes of test_skeletonize.py
#    from the fix commit, extracted at image build time; never part of this
#    task tree). The three authored hidden modules stay at their mounted
#    /tests/hidden paths: this package's editable-install import hook does not
#    serve files added to the tree at trial time, so the hidden modules run
#    from their own paths as top-level test modules. A pinned hash of the
#    exact bytes extracted from the fix commit catches tampering with
#    /opt/golden before the tree is modified.
GOT=$(sha256sum /opt/golden/test_skeletonize.py | cut -d' ' -f1)
[ "$GOT" = "$GOLDEN_SHA" ] || fail "golden regression test tampered with (sha256 $GOT)"
cp /opt/golden/test_skeletonize.py skimage/morphology/tests/test_skeletonize.py || fail "cannot plant golden regression test"
[ -f /tests/hidden/nonsquare/test_thin_hidden_nonsquare.py ] || fail "hidden case A missing"
[ -f /tests/hidden/partial/test_thin_hidden_partial.py ] || fail "hidden case B missing"
[ -f /tests/hidden/noncontig/test_thin_hidden_noncontig.py ] || fail "hidden case C missing"

# 6) the issue's exact reproduction snippet: after the fix the input array
#    must be untouched.
REPRO=$(python -c "import numpy as np; from skimage.morphology import thin; img=np.zeros((10,10),dtype=bool); img[2:8,2:8]=1; orig=img.copy(); thin(img); print('input_modified:', not np.array_equal(img,orig))" 2>&1)
echo "repro: $REPRO" >> "$LOG"
case "$REPRO" in
    *"input_modified: False"*) : ;;
    *) fail "reproduction still mutates the input array: '$REPRO'" ;;
esac

# 7) run the project's own pytest on the golden file and the hidden modules
#    (the hidden modules run from their mounted paths; the golden file runs
#    from inside the checked-out tree, replacing the parent's test file).
echo "=== pytest run ===" >> "$LOG"
if ! python -m pytest -p no:cacheprovider -v \
        /tests/hidden/nonsquare/test_thin_hidden_nonsquare.py \
        /tests/hidden/partial/test_thin_hidden_partial.py \
        /tests/hidden/noncontig/test_thin_hidden_noncontig.py \
        skimage/morphology/tests/test_skeletonize.py \
        > /logs/verifier/pytest.log 2>&1; then
    tail -40 /logs/verifier/pytest.log >&2
    fail "pytest exited non-zero on the planted regression + hidden tests (see pytest.log)"
fi
tail -5 /logs/verifier/pytest.log >> "$LOG"

# 8) belt: every required test must actually have RUN and PASSED (a skipped,
#    deselected or sabotaged test would leave no 'PASSED' line even though
#    pytest exited 0).
for t in \
    test_thin_copies_input\[bool\] \
    test_thin_copies_input\[float\] \
    test_thin_copies_input\[int\] \
    test_thin_nonsquare_preserves_input \
    test_thin_nonsquare_deterministic \
    test_thin_partial_iter1_preserves_input \
    test_thin_partial_iter2_preserves_input \
    test_thin_partial_iter4_preserves_input \
    test_thin_full_disc_preserves_input \
    test_thin_partial_budget_calls_do_not_accumulate \
    test_thin_strided_view_preserves_base_buffer \
    test_thin_reversed_view_preserves_base \
    test_thin_transposed_view_preserves_base; do
    if ! grep -Fq "::${t} PASSED" /logs/verifier/pytest.log; then
        fail "required test ${t} did not run and pass (see pytest.log)"
    fi
done

echo 1 > /logs/verifier/reward.txt
exit 0