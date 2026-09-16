#!/bin/bash
# Verifier for ballast-overtake. On the agent's final tree at /app/src:
# (1) provenance — HEAD still the pinned parent commit, every tracked file
#     except networkx/algorithms/link_analysis/hits_alg.py byte-identical to
#     the parent blobs, no untracked non-ignored files;
# (2) /app/summary.md exists and is non-empty;
# (3) plant the upstream regression test (golden test_hits.py, extracted
#     from the fix commit at image build time; never part of this task tree)
#     and run the whole link-analysis test directory — the golden regression
#     test must actually have run and passed, and the project's other
#     tests must stay green;
# (4) run three authored hidden cases on other graphs (path_graph(5),
#     path_graph(8), disjoint union path_graph(5)+path_graph(2)) that on the
#     unfixed parent tree divide by zero with a RuntimeWarning and return
#     inf/nan; the fixed tree must return finite, non-negative scores equal
#     to the sign-canonicalized dominant-eigenvector normalization, with no
#     divide-by-zero warning.
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

PARENT=675034adb14a790336121e4e0f9d8097b880ec41
ALLOWED=networkx/algorithms/link_analysis/hits_alg.py

# Run every Python decision of this verifier in a site-independent process.
# The agent phase runs as root with site-packages writable, so an agent
# could otherwise plant a sitecustomize.py that intercepts _hits_numpy at
# interpreter startup and make every test pass while leaving the buggy
# tree at /app/src untouched (reproduced during review: reward 1 with the
# tree pristine). `python3 -S` skips the site module entirely (no
# sitecustomize import, no .pth processing); networkx resolves straight to
# /app/src and numpy/pytest to site-packages via an explicit PYTHONPATH.
SP=$(python3 -c 'import site; print(site.getsitepackages()[0])')
export PYTHONPATH="$SP:/app/src"

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in. This is a CONTENT check (hash the actual bytes against the parent
#    blobs), so assume-unchanged/skip-worktree tricks cannot hide a dirty
#    file; any untracked non-ignored file is refused too.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        "$ALLOWED") : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            if [ -L "$f" ]; then
                # Symlink blobs: the link target is stored as the blob's
                # content (upstream committed some targets with a trailing
                # newline, e.g. benchmarks/pyproject.toml), while the
                # working-tree link itself has no newline. Compare the
                # strings with trailing newlines stripped.
                have=$(readlink "$f")
                want_cont=$(git cat-file blob "$want" 2>/dev/null || true)
                if [ "$have" != "$want_cont" ]; then
                    echo "out-of-scope modified symlink target: $f ('$have' != '$want_cont')" >> "$LOG"; ok=0
                fi
                continue
            fi
            have=$(git hash-object -- "$f" 2>/dev/null || true)
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
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

# 3) deliverable: the agent's change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 3b) deliverable: the fix must actually live in the graded TREE. Reading
#     the body of _hits_numpy in /app/src (the interpreter executing under
#     python3 -S has no sitecustomize, so this reflects the real code being
#     graded), the assignment that feeds the max-scaling of each score
#     vector must go through np.abs sign-canonicalization. This is what
#     makes "fix the environment instead of the tree" a non-option.
if ! python3 -S - <<'PY'
import re
src = open("networkx/algorithms/link_analysis/hits_alg.py").read()
m = re.search(r"def _hits_numpy\(.*?(?=\ndef |\Z)", src, re.S)
assert m, "_hits_numpy not found in hits_alg.py"
body = m.group(0)
hlines = [l for l in body.splitlines() if re.match(r"\s*h\s*=", l)]
alines = [l for l in body.splitlines() if re.match(r"\s*a\s*=", l)]
assert any("np.abs" in l for l in hlines), "hub vector selection is not sign-canonicalized in the tree"
assert any("np.abs" in l for l in alines), "authority vector selection is not sign-canonicalized in the tree"
print("fix-in-tree: _hits_numpy sign-canonicalization present")
PY
then
    fail "fix not present in the graded tree (see verifier log)"
fi

# 3c) guard the golden seed: it is baked read-only into the image but the
#     root agent could rewrite /opt/golden/test_hits.py. Refuse to run a
#     golden file that lost the regression's actual assertions.
grep -q "def test_hits_numpy_normalized_false_finite" /opt/golden/test_hits.py \
    || fail "/opt/golden/test_hits.py lost the regression test"
grep -q "np.isfinite" /opt/golden/test_hits.py \
    || fail "/opt/golden/test_hits.py lost its finiteness assertions"
grep -q "v >= 0" /opt/golden/test_hits.py \
    || fail "/opt/golden/test_hits.py lost its non-negativity assertions"

# 4) plant the upstream regression test (golden bytes, extracted from the
#    fix commit at image build time; never part of this task tree) over the
#    project's own test_hits.py, then run the whole link-analysis test
#    directory (golden test_hits.py + the project's own test_pagerank.py).
cp /opt/golden/test_hits.py networkx/algorithms/link_analysis/tests/test_hits.py \
    || fail "cannot plant golden regression test"
if ! python3 -S -m pytest networkx/algorithms/link_analysis/ -v -p no:cacheprovider > /tmp/pytest.out 2>&1; then
    tail -40 /tmp/pytest.out >&2
    fail "project link-analysis tests failed after planting regression test (see /tmp/pytest.out)"
fi
# the golden regression test must have actually run and passed (a
# neutralised or skipped run would leave no PASSED line even though pytest
# exited 0).
grep -q "test_hits_numpy_normalized_false_finite PASSED" /tmp/pytest.out || {
    tail -40 /tmp/pytest.out >&2
    fail "golden regression test did not run and pass (see /tmp/pytest.out)"
}
grep -q "test_hits_numpy PASSED" /tmp/pytest.out \
    || fail "project's own test_hits_numpy did not pass (see /tmp/pytest.out)"

# 5) three authored hidden cases: other graphs reaching the same broken
#    scaling path (a 5-path, an 8-path, and a disconnected union of a
#    5-path with an edge). Each must exit 0, print exactly its expected
#    marker, and (by construction of the script) never emit a
#    divide-by-zero RuntimeWarning. On the unfixed parent tree every one of
#    these raises RuntimeWarning: divide by zero and returns inf/nan.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case/check.py" "$work/check.py" || fail "hidden case $name: missing check.py"
    cp "$case/expected" "$work/expected" || fail "hidden case $name: missing expected"
    ( cd /app/src && python3 -S "$work/check.py" > "$work/stdout.txt" 2> "$work/stderr.txt" )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: check.py exited $rc; stderr:" >> "$LOG"
        head -8 "$work/stderr.txt" >> "$LOG"
        tail -8 "$work/stdout.txt" >> "$LOG"
        fail "hidden case $name: check.py exited $rc (see $LOG)"
    fi
    if ! cmp -s "$work/stdout.txt" "$work/expected"; then
        echo "hidden case $name: marker mismatch; got:" >> "$LOG"
        od -c "$work/stdout.txt" | head -8 >> "$LOG"
        fail "hidden case $name: marker mismatch (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected 3"

echo "PASS: provenance, /app/summary.md, golden regression test + link-analysis suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0