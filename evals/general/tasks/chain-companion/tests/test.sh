#!/bin/bash
# Verifier for chain-companion: proves the agent's fix in the real nltk tree
# at /app/src by (1) asserting the verifier's own trust anchors (the python3 /
# git binaries it executes and the golden regression test still have the
# sha256 recorded at image build time), (2) asserting provenance (HEAD still
# the pinned parent commit; every tracked file except the single source file
# the bug lives in is byte-identical to it; no stray untracked files), (3)
# requiring the agent's own reproduction /app/repro.py, (4) running that
# reproduction against the repaired tree (must exit 0) and against a pristine
# pre-fix snapshot of the same package materialised from the pinned commit
# via `git archive` (must exit non-zero, proving the reproduction is genuine
# and not hardcoded), (5) running the project's own regression test for this
# bug (extracted from the fix commit at image build time into /opt/golden,
# sha256-pinned), (6) running the project's own existing tree-transforms test
# suite, and (7) running four authored hidden cases that reach the same code
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

PARENT=27b8ad6cd50a484590cb9409e5d2a891ab56e16c
GIT=git
PY=python3

# 0) integrity anchors. The verifier executes python3, git and the golden
#    regression test; an adversarial agent with write access to /usr/local or
#    /opt (e.g. a root-flavoured trial) could otherwise substitute any of
#    them. The pins recorded at image build time detect substitution before
#    anything is executed.
if ! ( cd / && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1 ) || \
   ! ( cd / && sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 ); then
    fail "toolchain or golden integrity check failed (substituted binary or test)"
fi

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit: no commits added,
#    and nothing can hide work from the blob-level scope check below.
if [ "$("$GIT" rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $("$GIT" rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (discovered by the agent, not named here). This is a CONTENT check,
#    not a git-status check: we hash the actual bytes of every tracked file
#    on disk against the pinned commit's own blob, so assume-unchanged /
#    skip-worktree tricks cannot hide a dirty file, and we refuse any
#    untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        nltk/tree/tree.py) : ;;
        *)
            want=$("$GIT" rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            if [ -L "$f" ]; then
                have=$(printf '%s' "$(readlink "$f")" | "$GIT" hash-object --stdin 2>/dev/null || true)
            else
                have=$("$GIT" hash-object -- "$f" 2>/dev/null || true)
            fi
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <("$GIT" ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <("$GIT" ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the bug's source file (see $LOG)"
fi

# 3) deliverable: the agent's own reproduction must exist, be non-empty and
#    actually drive the parser API named in the contract (a script that never
#    calls Tree.fromstring cannot demonstrate the bug) and must assert the
#    round-trip property rather than merely invoking the parser.
[ -s /app/repro.py ] || fail "/app/repro.py is missing or empty"
grep -q "Tree.fromstring" /app/repro.py || fail "/app/repro.py never calls Tree.fromstring"
grep -q "assert" /app/repro.py || fail "/app/repro.py contains no assertion (a smoke script cannot demonstrate the bug)"

# 4a) the reproduction must PASS against the repaired tree.
if ! "$PY" /app/repro.py > /tmp/repro.out 2> /tmp/repro.err; then
    echo "reproduction failed on the repaired tree; stderr tail:" >> "$LOG"
    tail -12 /tmp/repro.err >> "$LOG"
    tail -12 /tmp/repro.err >&2
    fail "reproduction /app/repro.py did not exit 0 on the repaired tree (see $LOG)"
fi

# 4b) the reproduction must FAIL against a pristine pre-fix snapshot of the
#     package, materialised from the pinned commit itself (git archive uses
#     the commit tree, so it is immune to any working-tree edits). This
#     proves the reproduction is sensitive to the bug and not hardcoded.
rm -rf /tmp/prefix && mkdir -p /tmp/prefix
if ! "$GIT" archive HEAD nltk | tar -x -C /tmp/prefix; then
    fail "could not materialise pristine pre-fix snapshot from pinned commit"
fi
if ! ( cd / && PYTHONPATH=/tmp/prefix "$PY" -c "import nltk; print(nltk.__file__)" 2>/dev/null | grep -q "^/tmp/prefix/" ); then
    fail "pre-fix snapshot did not shadow the installed package (import resolution broken)"
fi
if PYTHONPATH=/tmp/prefix "$PY" /app/repro.py > /tmp/repro_pre.out 2> /tmp/repro_pre.err; then
    tail -5 /tmp/repro_pre.out >&2
    fail "reproduction exited 0 against the pre-fix snapshot; not a genuine reproduction (hardcoded?)"
fi
if grep -qi "importerror" /tmp/repro_pre.err; then
    tail -8 /tmp/repro_pre.err >&2
    fail "reproduction failed against the pre-fix snapshot for import reasons, not for the bug"
fi
echo "reproduction passes on repaired tree, fails on pristine pre-fix snapshot"

# 5) the project's own regression test for this bug (from /opt/golden, added
#    upstream with the fix, sha256-pinned) must pass 4/4 on the repaired tree.
"$PY" -m pytest -q -p no:cacheprovider /opt/golden/test_tree_golden.py > /tmp/golden.out 2>&1 || {
    tail -20 /tmp/golden.out >&2
    fail "upstream regression test for this bug did not pass (see /tmp/golden.out)"
}
grep -q "4 passed" /tmp/golden.out || {
    tail -20 /tmp/golden.out >&2
    fail "upstream regression run did not report 4 passed (see /tmp/golden.out)"
}

# 6) the project's own existing tree-transforms test suite must stay green.
"$PY" -m pytest -q -p no:cacheprovider nltk/test/unit/test_treetransforms.py > /tmp/existing.out 2>&1 || {
    tail -20 /tmp/existing.out >&2
    fail "project's existing tree-transforms tests failed (see /tmp/existing.out)"
}
grep -q "5 passed" /tmp/existing.out || {
    tail -20 /tmp/existing.out >&2
    fail "existing tree-transforms run did not report 5 passed (see /tmp/existing.out)"
}

# 7) authored hidden cases: other inputs reaching the same parse path, from
#    inputs the upstream regression test does not use (escaped brackets in
#    nested leaves and labels; a custom bracket pair). Each check.py parses
#    its input.txt with the project's own parser and asserts the exact tree
#    structure and round-trip. On the pre-fix code every one of these inputs
#    either raises or silently mis-parses.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    if ! "$PY" "$case/check.py" "$case/input.txt" > /tmp/hc.out 2> /tmp/hc.err; then
        echo "hidden case $name: check.py failed; stderr tail:" >> "$LOG"
        tail -12 /tmp/hc.err >> "$LOG"
        tail -12 /tmp/hc.err >&2
        fail "hidden case $name failed (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 4 ] || fail "only $CASES hidden case(s) ran; expected 4"

echo "PASS: provenance, /app/repro.py, repro both directions, upstream regression test, existing suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0