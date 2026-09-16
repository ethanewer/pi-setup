#!/bin/bash
# Verifier for sheer-drift: proves the agent's fix in the real
# BurntSushi/ripgrep tree at /app/src by (1) asserting the verifier's own
# trust anchors (the golden regression test, the pre-fix binary and the
# toolchain still have the sha256 hashes pinned at image build time), (2)
# asserting provenance (HEAD still the pinned parent commit; the upstream fix
# commit is not reachable from this clone; every tracked file except the
# single source file the bug lives in is byte-identical to the parent commit;
# no stray untracked files), (3) requiring /app/repro.sh and /app/summary.md,
# (4) forcing a relink from the agent's sources (`touch` on the source file
# plus removal of the stale binary, then `cargo build --release --locked`,
# so anything the agent planted under target/ cannot survive and the executed
# binary is provably built from the agent's sources), (5) running the agent's
# own reproduction against the repaired binary (must pass) and against a
# pristine pre-fix binary baked at /opt/prefix/rg (must fail - this proves
# the symptom is real and the reproduction targets it), (6) planting the
# project's own regression test for this bug (r1765: tests/regression.rs at
# the fix commit, extracted at image build time into /opt/golden,
# sha256-pinned) and running the whole existing regression module (72 tests
# at the fix commit's tree, including r1765), (7) running the printer crate's
# own unit test suite, and (8) running three authored hidden CLI cases that
# reach the same CRLF printer code path from inputs the upstream test does
# not use, asserting byte-exact stdout.
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

PARENT=e6cac8b119d0d50646b3ba1aaf53e648c779901a
FIX=12dd455ee9aa731acfeb0d2dfed568a0103cae73

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the tree, the golden test, the
#    pre-fix binary and (via the project's own build and test scripts) the
#    toolchain; an adversarial agent with write access to /opt or /usr (e.g.
#    a root trial) could otherwise replace /opt/prefix/rg with a binary that
#    reproduces no bug (so the pre-fix direction check fails to fail), tamper
#    with the golden test, or swap the compiler for a stub that fakes a green
#    run. The pins recorded at image build time detect any substitution
#    before anything is executed.
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
#    lives in (discovered by the agent, not named here). This is a CONTENT
#    check, not a git-status check: the actual bytes of every tracked file on
#    disk are hashed against the pinned commit's own blob, so
#    assume-unchanged / skip-worktree tricks cannot hide a dirty file, and
#    any untracked non-ignored file is refused.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        crates/printer/src/standard.rs) : ;;  # the one source file the bug lives in
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

# 4) force a relink from the agent's sources. Touching the source file forces
#    cargo to recompile the affected crate and removing the binary forces it
#    to relink, so a planted prebuilt binary cannot survive and a tree that
#    does not compile fails here. No network is available; the warm cargo
#    cache in /opt/cargo (CARGO_HOME) and the pinned Cargo.lock make this an
#    offline incremental build.
touch /app/src/crates/printer/src/standard.rs || fail "cannot touch source"
rm -f /app/src/target/release/rg
if ! cargo build --release --locked > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cargo build failed on the agent's tree (see $LOG.build)"
fi
[ -x /app/src/target/release/rg ] || fail "/app/src/target/release/rg not produced by the rebuild"
if [ "$(od -An -tx1 -N4 /app/src/target/release/rg | tr -d ' \n')" != "7f454c46" ]; then
    fail "/app/src/target/release/rg is not a real ELF executable (planted wrapper?)"
fi

# 5) the agent's reproduction, both directions. Against the repaired binary
#    it must pass - exit 0 AND non-empty stdout. Against the pristine pre-fix
#    binary baked into the image it must fail - any exit 0 there means the
#    reproduction is fake/hardcoded or the symptom is not what we think it is.
if ! bash /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
RG_BIN=/opt/prefix/rg bash /app/repro.sh > /tmp/repro_prefix.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "agent repro passed against the PRE-FIX binary (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi

# 6) plant the upstream regression test (golden bytes, extracted from the fix
#    commit at image build time and sha256-pinned; never part of this task
#    tree) over the tree's copy of tests/regression.rs, then run the whole
#    pre-existing regression module. r1765 is the upstream test for this
#    defect; the other 71 tests are the module as it existed before the fix,
#    so a green run proves the fix broke nothing else.
cp /opt/golden/regression.rs /app/src/tests/regression.rs \
    || fail "cannot plant golden regression.rs"
if ! ( cd /app/src && cargo test --release --test integration -- regression > "$LOG.golden" 2>&1 ); then
    tail -30 "$LOG.golden" >&2
    fail "regression module (with r1765) did not pass (see $LOG.golden)"
fi
grep -q "^test regression::r1765 .* ok" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "the upstream regression test r1765 did not run and pass (see $LOG.golden)"
}
grep -q "test result: ok. 72 passed; 0 failed" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "regression module did not report 72 passed (expected 71 existing + r1765)"
}

# 7) the printer crate's own unit test suite must stay green (proves the fix
#    broke nothing inside the crate the bug lives in).
if ! ( cd /app/src && cargo test --release -p grep-printer > "$LOG.printer" 2>&1 ); then
    tail -30 "$LOG.printer" >&2
    fail "printer crate unit tests did not pass (see $LOG.printer)"
fi
grep -q "test result: ok\." "$LOG.printer" || {
    tail -20 "$LOG.printer" >&2
    fail "printer crate unit tests did not report a passing run (see $LOG.printer)"
}

# 8) four authored hidden CLI cases exercising the same CRLF line-terminator
#    printer path from inputs the upstream test does not use (blank line in
#    the middle of content lines; an all-blank file; matches fed through
#    stdin; and the byte-exact colored output of a real CRLF file with a
#    non-empty match, which pinpoints the carriage-return trim that a lazy
#    'delete the trim' fix would byte-identically mask on LF-only inputs),
#    each asserted byte-exact against the repaired binary's output.
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
[ "$CASES" -ge 4 ] || fail "only $CASES hidden case(s) ran; expected 4"

echo "PASS: provenance, fix-unreachable, scope, deliverables, rebuild, repro both directions, upstream regression test, printer unit tests, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0