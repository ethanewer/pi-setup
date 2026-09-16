#!/bin/bash
# Verifier for tumblehome-crest: proves the agent's fix in the real
# python/mypy tree at /app/src by
#  (0) asserting the verifier's own trust anchors (sha256 pins recorded at
#      image build time for the golden regression test, the pre-fix source
#      file, and the interpreter/toolchain) are still intact,
#  (1) asserting provenance: HEAD is still the pinned parent commit and the
#      upstream fix commit is not reachable from this clone,
#  (2) asserting scope: every tracked file except the one source file the bug
#      lives in (mypy/checker.py) is byte-identical to the pinned parent
#      commit (index oid AND worktree bytes, so assume-unchanged /
#      skip-worktree tricks cannot hide a dirty file) and no untracked
#      non-ignored files were added,
#  (3) requiring the deliverable /app/repro.py,
#  (4) running the agent's own reproduction against the repaired tree (must
#      report Success) and against a pristine PRE-FIX tree baked at
#      /opt/prefix-mypy-src (must report the false positive - this proves the
#      symptom is real, the reproduction targets it, and the fix is in the
#      tree, not in the reproduction),
#  (5) planting the upstream project's own regression test for this bug
#      (check-narrowing.test extracted from the fix commit at image build time
#      into /opt/golden, sha256-pinned) and running it (must pass),
#  (6) running the project's existing narrowing test subset to prove the fix
#      broke nothing else,
#  (7) running four authored hidden cases that reach the same negative
#      narrowing code path from inputs the upstream test does not use.
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

PARENT=0007c5267287ba47a3e4acc022ecb149fcf702e2
FIX=b7a8bab4e5385adf2457f6644aa70a8fceab9113
PY3=/usr/local/bin/python3

export PYTHONDONTWRITEBYTECODE=1

# 0) integrity anchors. The verifier executes the tree, the golden test, the
#    pre-fix tree and (via mypy/pytest) the interpreter; an adversarial agent
#    with write access to /opt or /usr (e.g. a root trial) could otherwise
#    substitute the golden test, the pre-fix tree, or the python binary for a
#    stub that fakes a green run. The sha256 pins recorded at image build time
#    detect any substitution before anything is executed.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/prefix-checker.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden, pre-fix source or toolchain integrity check failed (substituted file)"
fi

cd /app/src || fail "/app/src is missing"

# 1) provenance: the tree must still be at the pinned parent commit (no
#    commits added) and the upstream fix commit must not be reachable from
#    this object store (an agent that fetched or grafted the fix earns 0).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# 2) scope: every change must live in exactly the one source file the bug
#    lives in (mypy/checker.py, discovered by the agent, not named here).
#    Content check, not a git-status check: the actual bytes of every tracked
#    file on disk are hashed against the pinned commit's own blob, so
#    assume-unchanged / skip-worktree tricks cannot hide a dirty file, and any
#    untracked non-ignored file is refused.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        mypy/checker.py) : ;;  # the one source file the bug lives in
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            # Index oid first: authoritative for gitlink (submodule) entries,
            # whose on-disk dir is an empty placeholder never materialised by
            # a shallow checkout. Catches any index-level substitution.
            idx=$(git ls-files -s -- "$f" | awk '{print $2}')
            mode=$(git ls-files -s -- "$f" | awk '{print $1}')
            if [ "$idx" != "$want" ]; then
                echo "index oid mismatch for tracked file: $f" >> "$LOG"; ok=0; continue
            fi
            is_gitlink=0
            case "$mode" in
                160000*) is_gitlink=1 ;;
            esac
            if [ "$is_gitlink" -eq 0 ]; then
                # Worktree bytes for real files (catches assume-unchanged /
                # skip-worktree tricks on regular and symlink files).
                case "$mode" in
                    120000*)
                        have=$(printf '%s' "$(readlink "$f")" | git hash-object --stdin 2>/dev/null || true)
                        ;;
                    *)
                        have=$(git hash-object -- "$f" 2>/dev/null || true)
                        ;;
                esac
                if [ -z "$have" ] || [ "$have" != "$want" ]; then
                    echo "worktree differs from parent for tracked file: $f" >> "$LOG"; ok=0
                fi
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

# 3) deliverables: the agent's own failing reproduction.
[ -s /app/repro.py ] || fail "/app/repro.py is missing or empty"

# 4) the agent's reproduction, both directions. Against the repaired tree it
#    must pass (exit 0 AND report Success). Against the pristine pre-fix tree
#    baked into the image it must fail WITH the unreachable diagnostic - any
#    exit 0 there means the reproduction is fake/hardcoded or the symptom is
#    not what we think it is. The pristine tree is read-only and sha256-pinned
#    at build time, so the failing direction cannot be faked by editing it.
r1=$(mktemp -d /tmp/repro-fixed.XXXXXX)
if ! "$PY3" -m mypy --no-incremental --warn-unreachable --cache-dir="$r1" /app/repro.py > "$LOG.repro.fixed" 2>&1; then
    echo "reproduction failed on the repaired tree; stdout:" >> "$LOG"
    tail -10 "$LOG.repro.fixed" >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG.repro.fixed)"
fi
grep -q "Success: no issues found" "$LOG.repro.fixed" || {
    echo "no Success verdict on the repaired tree:" >> "$LOG"
    tail -10 "$LOG.repro.fixed" >> "$LOG"
    fail "agent repro did not report Success on the repaired tree (see $LOG.repro.fixed)"
}
r2=$(mktemp -d /tmp/repro-prefix.XXXXXX)
( cd /opt/prefix-mypy-src && "$PY3" -m mypy --no-incremental --warn-unreachable --cache-dir="$r2" /app/repro.py > "$LOG.repro.prefix" 2>&1 )
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "reproduction passed against the PRE-FIX tree; stdout:" >> "$LOG"
    tail -10 "$LOG.repro.prefix" >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG.repro.prefix)"
fi
grep -q "Statement is unreachable" "$LOG.repro.prefix" || {
    echo "pre-fix run did not show the unreachable diagnostic:" >> "$LOG"
    tail -10 "$LOG.repro.prefix" >> "$LOG"
    fail "agent repro did not reproduce the false positive on the pre-fix tree (see $LOG.repro.prefix)"
}

# 5) plant the upstream regression test (golden bytes, extracted from the fix
#    commit at image build time and sha256-pinned; never part of this task
#    tree) over the tree's copy of check-narrowing.test, then run the case
#    the upstream fix added. It must pass on the repaired tree.
cp /opt/golden/check-narrowing.test /app/src/test-data/unit/check-narrowing.test \
    || fail "cannot plant golden check-narrowing.test"
if ! "$PY3" -m pytest mypy/test/testcheck.py -k testNegativeNarrowingInContainer -q > "$LOG.golden" 2>&1; then
    tail -25 "$LOG.golden" >&2
    fail "upstream regression test testNegativeNarrowingInContainer did not pass (see $LOG.golden)"
fi
grep -q "1 passed" "$LOG.golden" || {
    tail -15 "$LOG.golden" >&2
    fail "golden run did not report 1 passed (see $LOG.golden)"
}

# 6) the project's existing narrowing test subset must stay green on the
#    repaired tree - this includes cases asserting valid negative narrowing is
#    preserved (e.g. testNarrowingOptionalEqualsNone), so an over-broad fix
#    that disables narrowing entirely fails here.
if ! "$PY3" -m pytest mypy/test/testcheck.py -k 'Narrowing or Narrow' -q > "$LOG.subset" 2>&1; then
    tail -25 "$LOG.subset" >&2
    fail "narrowing suite subset did not pass on the repaired tree (see $LOG.subset)"
fi
grep -q "passed" "$LOG.subset" || {
    tail -15 "$LOG.subset" >&2
    fail "subset run did not report a passing summary (see $LOG.subset)"
}

# 7) authored hidden cases: variations reaching the same negative-narrowing
#    code path from inputs the upstream test does not use. Each must report
#    Success (exit 0). The two container variants would fail on the broken
#    tree; the tuple-singleton variant must KEEP narrowing (soundness guard).
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=$(mktemp -d /tmp/hc-${name}.XXXXXX)
    cp -r "$case" "$work/case" || fail "hidden case $name: missing files"
    ( cd "$work/case" && bash run.sh > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: exited $rc (expected 0); stdout:" >> "$LOG"
        tail -15 "$work/case/stdout.txt" >> "$LOG"
        echo "stderr:" >> "$LOG"
        tail -15 "$work/case/stderr.txt" >> "$LOG"
        fail "hidden case $name: exited $rc (see $LOG)"
    fi
    rm -rf "$work"
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 2 ] || fail "only $CASES hidden case(s) ran; expected at least 2"

# 8) restore the test-data file so the tree is left as delivered.
cp /opt/prefix-mypy-src/test-data/unit/check-narrowing.test /app/src/test-data/unit/check-narrowing.test 2>/dev/null || true

echo "PASS: provenance, fix-unreachable, scope, deliverables, repro both directions, upstream regression test, narrowing subset, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0