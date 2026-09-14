#!/bin/bash
# Verifier for quoin-swell: proves the agent's fix in the real sharkdp/fd
# tree at /app/src by (1) asserting the verifier's own trust anchors (the
# golden regression test and the pre-fix binary still have the sha256 pinned
# at image build time), (2) asserting provenance (HEAD still the pinned
# parent commit; the upstream fix commit is not reachable from this clone;
# every tracked file except the single source file the bug lives in is
# byte-identical to the parent commit; no stray untracked files), (3)
# requiring /app/repro.sh and /app/summary.md, (4) forcing a rebuild of the
# tree (`touch` + `cargo build -j1`, fully offline) so the executed binary is
# provably built from the agent's sources, (5) running the agent's own
# reproduction against the repaired binary (must pass) and against a pristine
# pre-fix binary baked at /opt/prefix/fd (must fail - this proves the symptom
# is real and the reproduction targets it), (6) planting the upstream
# project's own regression test for this bug (tests/tests.rs extracted from
# the fix commit at image build time into /opt/golden, sha256-pinned) and
# running the whole test suite with `--skip test_exec_nulls` (that one test
# is a known 1-CPU sandbox artifact: it fails on the pristine parent tree too,
# cf. difficulty.json notes), and (7) running four authored hidden CLI cases
# that reach the same dash-search-path code path from inputs the upstream
# test does not use - each must pass on the repaired binary AND fail on the
# pre-fix binary.
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

PARENT=7f1b1471d5e3f88087eaad77885dc70968750bb3
FIX=8dfa67a245b08a2c0ea1e6381c0086768470f317
export PATH=/opt/cargo/bin:$PATH CARGO_HOME=/opt/cargo RUSTUP_HOME=/opt/rustup CARGO_NET_OFFLINE=true

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the tree, the golden test, the
#    pre-fix binary and (via cargo) the toolchain; an adversarial root agent
#    could otherwise replace /opt/prefix/fd with a binary that reproduces no
#    bug (so the pre-fix direction check fails to fail), tamper with the
#    golden test, or swap the toolchain for a stub that fakes a green run.
#    The pins recorded at image build time detect any substitution.
if [ ! -f /opt/pins/golden.sha256 ] || \
   ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/prefix-fd.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden, prefix-binary or toolchain integrity check failed (substituted file)"
fi

# 1) provenance: the tree must still be at the pinned parent commit (no
#    commits added) and the upstream fix commit must not be reachable from
#    this object store (an agent that fetched or grafted the fix earns 0; the
#    fix direction must come from the agent's own work).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# 2) scope: every change must live in exactly the one source file the bug
#    lives in (discovered by the agent, not named here). This is a CONTENT
#    check, not a git-status check: the actual bytes of every tracked file on
#    disk are hashed against the pinned commit's own blob, so
#    assume-unchanged / skip-worktree tricks cannot hide a dirty file, and
#    any untracked non-ignored file is refused.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        src/cli.rs) : ;;  # the one source file the bug lives in
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

# 4) forced rebuild from the agent's sources, fully offline. Touching the
#    (possibly fixed) source file before building means cargo recompiles the
#    library and relinks the binary from the tree as delivered; a planted
#    prebuilt binary or object file cannot survive, and a tree that does not
#    compile fails here.
touch src/cli.rs
if ! cargo build -j1 > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cargo build failed on the agent's tree (see $LOG.build)"
fi
[ -x /app/src/target/debug/fd ] || fail "/app/src/target/debug/fd not produced by the rebuild"
if [ "$(od -An -tx1 -N4 /app/src/target/debug/fd | tr -d ' \n')" != "7f454c46" ]; then
    fail "/app/src/target/debug/fd is not a real ELF executable (planted wrapper?)"
fi

# 5) the agent's reproduction, both directions. Against the repaired binary
#    it must pass - exit 0 AND the captured output contains ./-/foo.txt.
#    Against the pristine pre-fix binary baked into the image it must fail -
#    any exit 0 there means the reproduction is fake/hardcoded or the symptom
#    is not what the task says it is.
if ! bash /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
FD_BIN=/opt/prefix/fd bash /app/repro.sh > /tmp/repro_prefix.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "agent repro passed against the PRE-FIX binary (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi

# 6) plant the upstream regression test (golden bytes, extracted from the fix
#    commit at image build time and sha256-pinned; never part of this task
#    tree) over the tree's copy of tests/tests.rs, then run the whole suite
#    with only the known 1-CPU-bound exception skipped.
cp /opt/golden/tests.rs tests/tests.rs \
    || fail "cannot plant golden tests.rs"
if ! cargo test -j1 -- --skip test_exec_nulls > "$LOG.suite" 2>&1; then
    tail -40 "$LOG.suite" >&2
    fail "test suite (with planted upstream regression test) did not pass (see $LOG.suite)"
fi
grep -q "test test_single_dash_root_path ... ok" "$LOG.suite" || {
    tail -20 "$LOG.suite" >&2
    fail "the upstream regression test did not actually run and pass (see $LOG.suite)"
}
grep -q "test result: ok. 139 passed; 0 failed" "$LOG.suite" || {
    tail -20 "$LOG.suite" >&2
    fail "the project's unit tests are not green (see $LOG.suite)"
}
grep -q "test result: ok. 108 passed; 0 failed" "$LOG.suite" || {
    tail -20 "$LOG.suite" >&2
    fail "the integration suite is not green (expected 108 passed, 1 filtered) (see $LOG.suite)"
}

# 7) authored hidden CLI cases: nested dash dirs, filtered pattern, dash path
#    alongside another search path, and the --search-path long-option form -
#    all reaching the same dash-search-path code path from inputs the
#    upstream regression test does not use. Each must PASS on the repaired
#    binary and FAIL on the pristine pre-fix binary (proving the case really
#    targets the defect, so passing the golden test alone is insufficient).
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    [ -f "$case/run.sh" ] || fail "hidden case $name: missing run.sh"
    # repaired direction
    FD_BIN=/app/src/target/debug/fd bash "$case/run.sh" > /tmp/hc-$name.out 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: exited $rc on the repaired binary (expected 0); stdout:" >> "$LOG"
        head -15 /tmp/hc-$name.out >> "$LOG"
        fail "hidden case $name: exited $rc on the repaired binary (see $LOG)"
    fi
    # pre-fix direction: must fail
    FD_BIN=/opt/prefix/fd bash "$case/run.sh" > /tmp/hc-$name.prefix.out 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "hidden case $name: PASSED on the pre-fix binary (expected failure)" >> "$LOG"
        tail -15 /tmp/hc-$name.prefix.out >> "$LOG"
        fail "hidden case $name: passed on the pre-fix binary (case does not target the bug)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 2 ] || fail "only $CASES hidden case(s) ran; expected at least 2"

echo "PASS: provenance, fix-unreachable, scope, deliverables, offline rebuild, repro both directions, upstream regression test, full suite, and all hidden cases in both directions"
echo 1 > /logs/verifier/reward.txt
exit 0