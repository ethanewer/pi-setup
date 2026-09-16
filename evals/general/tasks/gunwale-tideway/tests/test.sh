#!/bin/bash
# Verifier for gunwale-tideway: proves the agent's fix in the real git/git
# tree at /app/src by (1) asserting the verifier's own trust anchors (the
# golden regression test and the pre-fix binary still have the sha256 pinned
# at image build time), (2) asserting provenance (HEAD still the pinned
# parent commit; the upstream fix commit is not reachable from this clone;
# every tracked file except the single source file the bug lives in is
# byte-identical to the parent commit; no stray untracked files), (3)
# requiring /app/repro.sh and /app/summary.md, (4) forcing a CLEAN rebuild
# from the source tree (`make clean` then `make -j1`, so nothing the agent
# planted under the git-ignored build output can survive and the executed
# binary is provably built from the agent's sources), (5) running the
# agent's own reproduction against the repaired binary (must pass) and
# against a pristine pre-fix binary baked at /opt/prefix/git (must fail -
# this proves the symptom is real and the reproduction targets it), (6)
# planting the upstream project's own regression test for this bug
# (t/t5514-fetch-multiple.sh extracted from the fix commit at image build
# time into /opt/golden, sha256-pinned) and running the whole t5514 suite,
# (7) running previously-existing fetch/pull suites t5510-fetch.sh,
#    t5513-fetch-track.sh and t5520-pull.sh, and (8) running three authored hidden CLI cases that
# reach the same multi-remote parallel-fetch code path from inputs the
# upstream test does not use.
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

PARENT=d9d677b2d8cc5f70499db04e633ba7a400f64cbf
FIX=c39952b925ccf59e49f3c174861a862dc1721492

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the tree, the golden test, the
#    pre-fix binary and (via the project's own build and test scripts) the
#    toolchain; an adversarial agent with write access to /opt or /usr (e.g.
#    a root trial) could otherwise replace /opt/prefix/git with a binary that
#    reproduces no bug (so the pre-fix direction check fails to fail), tamper
#    with the golden test, or swap the compiler / test shell for a stub that
#    fakes a green run. The pins recorded at image build time detect any
#    substitution before anything is executed.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/prefix-git.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden, prefix-binary or toolchain integrity check failed (substituted file)"
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
#    lives in (the fetch front-end, discovered by the agent, not named
#    here). This is a CONTENT check, not a git-status check: the actual
#    bytes of every tracked file on disk are hashed against the pinned
#    commit's own blob, so assume-unchanged / skip-worktree tricks cannot
#    hide a dirty file, and any untracked non-ignored file is refused.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        builtin/fetch.c) : ;;  # the one source file the bug lives in
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

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) clean rebuild from the agent's sources. Everything the verifier is
#    about to execute is thrown away first (make clean) so the binary comes
#    from the tree as delivered; a planted prebuilt binary or object file
#    cannot survive, and a tree that does not compile fails here.
if ! make clean > "$LOG.clean" 2>&1; then
    tail -20 "$LOG.clean" >&2
    fail "make clean failed (see $LOG.clean)"
fi
if ! make -j1 > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "make failed on the agent's tree (see $LOG.build)"
fi
[ -x /app/src/git ] || fail "/app/src/git not produced by the rebuild"
if [ "$(od -An -tx1 -N4 /app/src/git | tr -d ' \n')" != "7f454c46" ]; then
    fail "/app/src/git is not a real ELF executable (planted wrapper?)"
fi

# 5) the agent's reproduction, both directions. Against the repaired binary
#    it must pass - exit 0 AND all remotes' refs fetched. Against the
#    pristine pre-fix binary baked into the image it must fail - any exit 0
#    there means the reproduction is fake/hardcoded or the symptom is not
#    what we think it is.
if ! bash /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
GIT_BIN=/opt/prefix/git bash /app/repro.sh > /tmp/repro_prefix.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "agent repro passed against the PRE-FIX binary (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi

# 6) plant the upstream regression test (golden bytes, extracted from the
#    fix commit at image build time and sha256-pinned; never part of this
#    task tree) over the tree's copy of t5514, then run the whole suite.
cp /opt/golden/t5514-fetch-multiple.sh t/t5514-fetch-multiple.sh \
    || fail "cannot plant golden t5514"
if ! ( cd t && ./t5514-fetch-multiple.sh > "$LOG.golden" 2>&1 ); then
    tail -30 "$LOG.golden" >&2
    fail "t5514 (with upstream regression test) did not pass (see $LOG.golden)"
fi
grep -q "passed all 13 test(s)" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "t5514 did not pass all 13 tests (see $LOG.golden)"
}
grep -q "ok 13 - git fetch --multiple --jobs=0 picks a default$" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "the upstream regression test did not actually run and pass (see $LOG.golden)"
}

# 7) previously-existing fetch/pull suites must stay green. The scope check
#    above guarantees these files are byte-identical to the pinned commit
#    (the agent never touched them), so a green run proves the fix broke
#    nothing else.
for suite in t5510-fetch.sh t5513-fetch-track.sh t5520-pull.sh; do
    if ! ( cd t && ./$suite > "$LOG.$suite" 2>&1 ); then
        tail -30 "$LOG.$suite" >&2
        fail "$suite did not pass (see $LOG.$suite)"
    fi
    grep -q "passed all [0-9][0-9]* test(s)" "$LOG.$suite" || {
        tail -20 "$LOG.$suite" >&2
        fail "$suite did not report a passing run (see $LOG.$suite)"
    }
done

# 8) three authored hidden CLI cases: more remotes, --tags, changed branch
#    tips between fetches, and an unreachable remote alongside a reachable
#    one - all reaching the same parallel multi-remote fetch path from
#    inputs the upstream regression test does not use. Each must exit 0.
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

echo "PASS: provenance, fix-unreachable, scope, deliverables, clean rebuild, repro both directions, upstream regression test, existing suites, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0