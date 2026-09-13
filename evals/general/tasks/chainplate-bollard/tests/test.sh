#!/bin/bash
# Verifier for chainplate-bollard — an upstream-clone debugging task on
# networkx/networkx (real bug: SpanningTreeIterator initialises its internal
# partition queue only from __iter__, so a direct next() call — legal per the
# iterator protocol — raises AttributeError on the first call).
#
# On the agent's final tree at /app/src:
#   1. provenance — HEAD still the pinned parent commit; the upstream fix
#      commit is not reachable from the working clone; every tracked file
#      except networkx/algorithms/tree/mst.py is byte-identical to the
#      parent blobs; no untracked non-ignored files; mst.py actually differs
#      (a fix is present);
#   2. /app/summary.md exists and is non-empty;
#   3. module origin — `import networkx` resolves under /app/src, so a fix
#      done outside the deliverable tree (e.g. in site-packages) cannot
#      fake a pass;
#   4. the upstream regression test extracted at image build time into
#      /opt/golden/test_mst.py (digest-checked) is planted over the tree's
#      own test_mst.py and the whole file runs: the regression test
#      test_next_without_iter must PASS and the project's pre-existing mst
#      tests must stay green;
#   5. three authored hidden cases drive the same direct-next() code path
#      from inputs the upstream test does not use: an unweighted 4-cycle
#      driven to exhaustion and counted against Kirchhoff's theorem, a
#      weighted wheel graph in both the minimum and maximum directions, and
#      a MultiGraph input.
#
# Review hardening:
#   * the golden bytes are digest-checked against the SHA-256 recorded at
#     image build time, so rewriting /opt/golden in place earns nothing;
#   * the loaded SpanningTreeIterator.__next__ must come from the
#     deliverable tree's own mst.py (a monkeypatch planted from any other
#     file is refused);
#   * the hidden cases execute in a pristine interpreter
#     (python3 -S + PYTHONPATH=/app/src) that imports no site module, so a
#     sitecustomize/.pth/usercustomize wrapper outside the tree cannot make
#     them pass while the tree stays unfixed;
#   * pytest and the hidden cases run straight from /app/src, and every run
#     exits non-zero at the parent commit, so a neutralised/absent fix cannot
#     produce reward 1.
#
# Reward is binary and written on every exit path (trap below).

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

PARENT=5d160909eeb42e9844496dd2bbd19b826d2242d7
FIX_SHA=46a639aeb9bd4db8da444bd6a532df567b9a73cc
ALLOWED=networkx/algorithms/tree/mst.py
GOLDEN=/opt/golden/test_mst.py
GOLDEN_SHA256=985c62908be34305e954fd3f747c65cdac344d2da791841cc1f949725440f132

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 1b) the fix must be the agent's own work: the upstream fix commit must not
#     be reachable from the working clone.
if git cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from /app/src; the answer was fetched, not implemented"
fi

# 1c) scope: every change must live in exactly the one source file the bug
#     is in. CONTENT check (hash the actual bytes against the parent blobs),
#     so assume-unchanged/skip-worktree tricks cannot hide a dirty file; any
#     untracked non-ignored file is refused too.
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

# the deliverable must actually contain a fix
if [ -z "$(git diff -- "$ALLOWED" 2>/dev/null || true)" ]; then
    fail "the deliverable /app/src is unchanged: mst.py has no fix"
fi

# 2) deliverable: the agent's change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 3) module origin: a fix that does not live in the deliverable tree
#    (e.g. a wrapper planted in site-packages) must not fool the verdict.
if python3 -c "
import networkx
nxfile = networkx.__file__
print('networkx from', nxfile)
assert nxfile.startswith('/app/src/'), nxfile
" > /tmp/origin.out 2>&1; then
    echo "ok: import networkx resolves under /app/src"
    sed 's/^/    /' /tmp/origin.out
else
    echo "FAIL: import networkx does not resolve to the deliverable:" >&2
    cat /tmp/origin.out | sed 's/^/    /' >&2
    fail "import networkx does not resolve under /app/src (see above)"
fi

# 4a) belt: the loaded __next__ must come from the deliverable tree's own
#     mst.py. A wrapper that monkeypatches the class from another file
#     (sitecustomize, a conftest, a site-packages shim) would show a
#     different code origin here and is refused, even before the hidden
#     cases which run in a pristine -S interpreter. This does not constrain
#     the fix shape: the only file an agent is allowed to change IS mst.py.
if ! python3 -c "
import inspect
import networkx.algorithms.tree.mst as m
src = inspect.getsourcefile(m.SpanningTreeIterator.__next__)
assert src == '/app/src/networkx/algorithms/tree/mst.py', src
print('ok: loaded __next__ comes from', src)
" > /tmp/origin2.out 2>&1; then
    echo "FAIL: loaded SpanningTreeIterator.__next__ does not come from the deliverable tree's mst.py (a wrapper was planted):" >&2
    cat /tmp/origin2.out | sed 's/^/    /' >&2
    fail "SpanningTreeIterator.__next__ does not come from /app/src/networkx/algorithms/tree/mst.py (see above)"
else
    cat /tmp/origin2.out
fi

# 4) golden: digest of the planted upstream regression test, then plant it
#    over the tree's own test file and run the whole file.
if [ ! -s "$GOLDEN" ]; then
    fail "golden regression test missing from image"
fi
if [ "$(/usr/bin/sha256sum "$GOLDEN" | awk '{print $1}')" != "$GOLDEN_SHA256" ]; then
    fail "/opt/golden/test_mst.py does not match the bytes extracted from the upstream fix commit (expected sha256 $GOLDEN_SHA256)"
fi
cp "$GOLDEN" networkx/algorithms/tree/tests/test_mst.py \
    || fail "cannot plant golden regression test"
if ! python -m pytest networkx/algorithms/tree/tests/test_mst.py -v -p no:cacheprovider > /tmp/pytest.out 2>&1; then
    tail -40 /tmp/pytest.out >&2
    fail "mst test file failed after planting the regression test (see /tmp/pytest.out)"
fi
# the golden regression test must have actually run and passed (a
# neutralised or skipped run would leave no PASSED line even though pytest
# exited 0).
grep -q "test_next_without_iter PASSED" /tmp/pytest.out || {
    tail -40 /tmp/pytest.out >&2
    fail "golden regression test did not run and pass (see /tmp/pytest.out)"
}
# the project's own pre-existing mst tests must also have run and passed.
grep -q "test_minimum_spanning_tree_iterator PASSED" /tmp/pytest.out \
    || fail "project's own test_minimum_spanning_tree_iterator did not pass (see /tmp/pytest.out)"

# 5) hidden cases: direct-next() drives of the same iterator that the
#    upstream regression test does not use. Each must exit 0 and print
#    exactly its expected marker. On the unfixed parent tree every one of
#    these raises AttributeError on the first next() call (exit 1).
CASES=0
for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case/check.py" "$work/check.py" || fail "hidden case $name: missing check.py"
    cp "$case/expected" "$work/expected" || fail "hidden case $name: missing expected"
    # Pristine interpreter: python3 -S skips the site module entirely, so no
    # sitecustomize/.pth/usercustomize wrapper planted outside the tree can
    # influence this run; PYTHONPATH hands the run the deliverable tree
    # itself. A wrapper-only "fix" (ambient monkeypatches, site-packages
    # shims, conftest tricks) is therefore invisible here and the real tree
    # bytes decide the verdict.
    ( cd /app/src && PYTHONPATH=/app/src python3 -S "$work/check.py" > "$work/stdout.txt" 2> "$work/stderr.txt" )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: check.py exited $rc; stderr:" >> "$LOG"
        head -12 "$work/stderr.txt" >> "$LOG"
        tail -12 "$work/stdout.txt" >> "$LOG"
        fail "hidden case $name: check.py exited $rc (see $LOG)"
    fi
    if ! cmp -s "$work/stdout.txt" "$work/expected"; then
        echo "hidden case $name: marker mismatch; got:" >> "$LOG"
        od -c "$work/stdout.txt" | head -8 >> "$LOG"
        fail "hidden case $name: marker mismatch (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 2 ] || fail "only $CASES hidden case(s) ran; expected 3"

echo "PASS: provenance, /app/summary.md, golden regression test + full mst test file, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0