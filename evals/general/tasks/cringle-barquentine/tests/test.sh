#!/bin/bash
# Verifier for cringle-barquentine: proves the agent's fix in the real
# BurntSushi/ripgrep tree at /app/src by (1) asserting the verifier's own
# trust anchors (the golden regression test, the pre-fix binary and the
# build/test toolchain still have the sha256 pinned at image build time), (2)
# asserting provenance (HEAD still the pinned parent commit; the upstream fix
# commit is not reachable from this clone; every tracked file except the one
# source file the bug lives in is byte-identical to the parent commit; no
# stray untracked files), (3) requiring /app/repro.sh and /app/summary.md,
# (4) forcing a CLEAN rebuild from the source tree (`cargo clean` then
# `cargo build --release -j1`, so nothing the agent planted under the
# git-ignored target/ can survive and the executed binary is provably built
# from the agent's sources), (5) running the agent's own reproduction against
# the repaired binary (must pass) and against a pristine pre-fix binary baked
# at /opt/prefix/rg (must fail - this proves the symptom is real and the
# reproduction targets it), (6) planting the upstream project's own
# regression test for this defect (tests/regression.rs extracted from the fix
# commit at image build time into /opt/golden, sha256-pinned) and running it,
# (7) running the full existing integration suite and the unit test suites of
# the grep-regex and grep-matcher crates (break-nothing proof), and (8)
# running three authored hidden CLI cases that reach the same word-matching
# empty-pattern code path from inputs the upstream test does not use, each
# required to pass on the agent's binary and to fail on the pre-fix binary.
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

export PATH=/opt/rust/bin:$PATH CARGO_HOME=/opt/rust CARGO_BUILD_JOBS=1

PARENT=5e81c60b35ce1481cdce5aa933b808faa71bc90e
FIX=bc76a30c23317526441a76f99ff397f65acea607

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the tree, the golden test, the
#    pre-fix binary and (via the project's own build and test scripts) the
#    toolchain; an adversarial agent with write access to /opt or /usr (e.g.
#    a root trial) could otherwise replace /opt/prefix/rg with a binary that
#    reproduces no bug (so the failure-direction checks stop failing), tamper
#    with the golden test, or swap the compiler / test shell for a stub that
#    fakes a green run. The pins recorded at image build time detect any
#    substitution before anything is executed.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/prefix-rg.sha256 >/dev/null 2>&1 || \
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
#    lives in (the word-matching code, discovered by the agent, not named
#    here). This is a CONTENT check, not a git-status check: the actual bytes
#    of every tracked file on disk are hashed against the pinned commit's own
#    blob, so assume-unchanged / skip-worktree tricks cannot hide a dirty
#    file, and any untracked non-ignored file is refused.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        crates/regex/src/word.rs) : ;;  # the one source file the bug lives in
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

# 4) clean rebuild from the agent's sources. Everything the verifier is about
#    to execute is thrown away first (cargo clean), so the binary comes from
#    the tree as delivered; a planted prebuilt binary or object file cannot
#    survive, and a tree that does not compile fails here.
if ! cargo clean > /dev/null 2>&1; then
    fail "cargo clean failed; cannot prove a from-source rebuild"
fi
if ! cargo build --release -j1 > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cargo build failed on the agent's tree (see $LOG.build)"
fi
[ -x /app/src/target/release/rg ] || fail "/app/src/target/release/rg not produced by the rebuild"
if [ "$(od -An -tx1 -N4 /app/src/target/release/rg | tr -d ' \n')" != "7f454c46" ]; then
    fail "/app/src/target/release/rg is not a real ELF executable (planted wrapper?)"
fi

# 5) the agent's reproduction, both directions. Against the repaired binary
#    it must pass - exit 0 AND exact expected stdout. Against the pristine
#    pre-fix binary baked into the image it must fail - any exit 0 there means
#    the reproduction is fake/hardcoded or the symptom is not what we think
#    it is.
if ! bash /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -30 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
if RG_BIN=/opt/prefix/rg bash /app/repro.sh > /tmp/repro_prefix.out 2>&1; then
    echo "agent repro passed against the PRE-FIX binary (expected failure); stdout:" >> "$LOG"
    head -30 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi

# 6) plant the upstream regression test (golden bytes, extracted from the fix
#    commit at image build time and sha256-pinned; never part of this task
#    tree) over the tree's copy of tests/regression.rs, then run it. The
#    sha256 check above already proved /opt/golden/regression.rs is the
#    pinned upstream file; requiring the test to run and pass proves the tree
#    reproduces the fixed behaviour.
cp /opt/golden/regression.rs /app/src/tests/regression.rs \
    || fail "cannot plant golden tests/regression.rs"
if ! cargo test --release -j1 -- r1891 > "$LOG.golden" 2>&1; then
    tail -30 "$LOG.golden" >&2
    fail "the planted upstream regression test r1891 did not pass (see $LOG.golden)"
fi
grep -q "test regression::r1891 ... ok" "$LOG.golden" || {
    tail -30 "$LOG.golden" >&2
    fail "the upstream regression test r1891 did not actually run and pass (see $LOG.golden)"
}
grep -q "test result: ok. 1 passed; 0 failed" "$LOG.golden" || {
    tail -30 "$LOG.golden" >&2
    fail "r1891 did not report exactly 1 passed (see $LOG.golden)"
}

# 7) break-nothing proof on the project's own machinery: the full integration
#    suite (272 tests = the 271 existing tests plus the planted r1891) and the
#    unit test suites of the two search crates must all pass.
if ! cargo test --release -j1 > "$LOG.suite" 2>&1; then
    tail -30 "$LOG.suite" >&2
    fail "the full integration suite did not pass (see $LOG.suite)"
fi
grep -q "test result: ok. 272 passed; 0 failed" "$LOG.suite" || {
    tail -30 "$LOG.suite" >&2
    fail "integration suite did not report all of 272 passed (see $LOG.suite)"
}
if ! cargo test --release -j1 -p grep-regex -p grep-matcher > "$LOG.units" 2>&1; then
    tail -30 "$LOG.units" >&2
    fail "grep-regex/grep-matcher unit suites did not pass (see $LOG.units)"
fi
if grep -E "[1-9][0-9]* failed" "$LOG.units" >/dev/null; then
    tail -30 "$LOG.units" >&2
    fail "a unit-suite test failed (see $LOG.units)"
fi

# 8) three authored hidden CLI cases: same word-matching empty-pattern code
#    path, from inputs the upstream regression test does not use (a different
#    input layout, and other empty-matchable patterns). Each must pass on the
#    agent's rebuilt binary AND must fail on the pristine pre-fix binary
#    (proving each case is a real regression detector on the unfixed tree).
CASES=0
for case in /tests/hidden/*/; do
    [ -f "$case/run.sh" ] || continue
    name=$(basename "$case")
    if ! bash "$case/run.sh" > /tmp/hc-fixed-$name.out 2>&1; then
        echo "hidden case $name failed on the repaired tree; output:" >> "$LOG"
        head -20 /tmp/hc-fixed-$name.out >> "$LOG"
        fail "hidden case $name did not pass on the repaired tree (see $LOG)"
    fi
    if RG_BIN=/opt/prefix/rg bash "$case/run.sh" > /tmp/hc-prefix-$name.out 2>&1; then
        echo "hidden case $name PASSED on the PRE-FIX binary (expected failure); output:" >> "$LOG"
        head -20 /tmp/hc-prefix-$name.out >> "$LOG"
        fail "hidden case $name does not detect the unfixed tree (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
if [ "$CASES" -lt 2 ]; then
    fail "fewer than two hidden cases executed ($CASES)"
fi

echo "ALL CHECKS PASSED"
echo "ALL CHECKS PASSED" >> "$LOG"
echo 1 > /logs/verifier/reward.txt
exit 0