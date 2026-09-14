#!/bin/bash
# Verifier for bosun-fathom: proves the agent's fix in the real
# BurntSushi/ripgrep tree at /app/src by (1) asserting the verifier's own
# trust anchors (the golden regression test, the pre-fix binary and the
# toolchain still have the sha256 hashes pinned at image build time), (2)
# asserting provenance (HEAD still the pinned parent commit; the upstream fix
# commit is not reachable from this clone; every tracked file except the
# single source file the bug lives in is byte-identical to the parent commit;
# no stray untracked files), (3) requiring /app/repro.sh and /app/summary.md,
# (4) forcing a relink from the agent's sources (`touch` on the source file
# plus removal of the stale binary and the searcher crate's build output,
# then `cargo build --locked`, so anything the agent planted under target/
# cannot survive and the executed binary is provably built from the agent's
# sources), (5) running the agent's own reproduction against the repaired
# binary (must pass) and against a pristine pre-fix binary baked at
# /opt/prefix/rg, both at its canonical path and at a copied path (must fail
# both ways - this proves the symptom is real, the reproduction targets it,
# and no path special-casing is doing the work), (6) planting the project's
# own regression test for this bug (r2944_incorrect_bytes_searched:
# tests/regression.rs at the fix commit, extracted at image build time into
# /opt/golden, sha256-pinned) and running that single test, (7) running the
# full integration suite (309 tests with the golden planted) and the searcher
# crate's own unit test suite, and (8) running three authored hidden CLI
# cases that reach the same early-stop byte-accounting code path from inputs
# the upstream test does not use (multiple files with per-file max-count,
# UTF-8 multibyte lines, CRLF line endings), each asserting an exact
# "N bytes searched" figure.
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

PARENT=6244e635a1a5aa4d401826b1e970d59a3f6cbf7c
FIX=4ab1862dc04783b6615807d4b4511388c6b30364

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
        crates/searcher/src/searcher/glue.rs) : ;;  # the one source file the bug lives in
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
            case "$mode" in
                160000*) : ;;  # gitlink entry: nothing to hash on disk
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

# 4) force a relink from the agent's sources. Touching the source file
#    forces cargo to recompile the affected crate, and removing the binary
#    and the searcher crate's build output forces it to relink, so a planted
#    prebuilt binary cannot survive and a tree that does not compile fails
#    here. No network is available; the warm cargo cache in /opt/cargo
#    (CARGO_HOME) and the pinned Cargo.lock make this an offline incremental
#    build.
touch /app/src/crates/searcher/src/searcher/glue.rs || fail "cannot touch source"
rm -f /app/src/target/debug/rg /app/src/target/debug/libgrep_searcher* || fail "cannot clear stale build output"
if ! cargo build --locked > "$LOG.relink" 2>&1; then
    tail -40 "$LOG.relink" >&2
    fail "cargo build failed on the agent's tree (see $LOG.relink)"
fi
[ -x /app/src/target/debug/rg ] || fail "/app/src/target/debug/rg not produced by the relink"
if [ "$(od -An -tx1 -N4 /app/src/target/debug/rg | tr -d ' \n')" != "7f454c46" ]; then
    fail "/app/src/target/debug/rg is not a real ELF executable (planted wrapper?)"
fi

# 5) the agent's reproduction, both directions. Against the repaired binary
#    it must pass - exit 0 AND the asserted stats figures. Against the
#    pristine pre-fix binary it must fail - any exit 0 there means the
#    reproduction is fake/hardcoded or the symptom is not what we think it
#    is. The pre-fix binary is also run from a copy under a different path so
#    that a reproduction special-casing /opt/prefix cannot pass this check.
if ! bash /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -12 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
for PFX in /opt/prefix/rg /tmp/prefixcopy/rg; do
    if [ "$PFX" = "/tmp/prefixcopy/rg" ]; then
        mkdir -p /tmp/prefixcopy || fail "cannot create prefix copy dir"
        cp /opt/prefix/rg /tmp/prefixcopy/rg || fail "cannot copy pre-fix binary"
    fi
    RG_BIN="$PFX" bash /app/repro.sh > /tmp/repro_prefix.out 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "agent repro passed against the PRE-FIX binary at $PFX (expected failure); stdout:" >> "$LOG"
        head -12 /tmp/repro_prefix.out >> "$LOG"
        fail "agent repro did not fail on the pre-fix binary (see $LOG)"
    fi
done

# 6) plant the upstream regression test (golden bytes, extracted from the
#    fix commit at image build time and sha256-pinned; never part of this
#    task tree) over the tree's copy of tests/regression.rs, then run the
#    single regression test it adds. The tree's pre-existing regression
#    tests keep their bytes (the golden file only ADDS r2944 on top of the
#    parent's file).
cp /opt/golden/regression.rs /app/src/tests/regression.rs \
    || fail "cannot plant golden regression module"
if ! cargo test --test integration -- r2944_incorrect_bytes_searched \
        > "$LOG.golden" 2>&1; then
    tail -30 "$LOG.golden" >&2
    fail "r2944 (upstream regression test) did not pass (see $LOG.golden)"
fi
grep -q "regression::r2944_incorrect_bytes_searched ... ok" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "the upstream regression test did not actually run and pass (see $LOG.golden)"
}
grep -q "1 passed; 0 failed" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "the golden test run did not report 1 passed, 0 failed (see $LOG.golden)"
}

# 7) the whole project suite with the golden planted, plus the searcher
#    crate's own unit suite. The scope check above guarantees tests/ is
#    byte-identical to the pinned commit apart from the planted golden
#    (which only appends r2944), so a green run proves the fix broke
#    nothing else.
# The full suite is run with `--skip accessed`, excluding exactly the two
# access-time sort tests (sort_accessed, sortr_accessed): they sort by file
# access time with 100 ms sleeps and are nondeterministic under this
# container's atime semantics (observed flaky even on the pristine pinned
# tree), so they cannot gate the agent's fix. All other 307 tests (309
# with the planted golden r2944) must pass.
if ! cargo test --test integration -- --skip accessed > "$LOG.integration" 2>&1; then
    tail -30 "$LOG.integration" >&2
    fail "full integration suite did not pass (see $LOG.integration)"
fi
grep -q "test result: ok. 307 passed; 0 failed" "$LOG.integration" || {
    tail -20 "$LOG.integration" >&2
    fail "full integration suite did not report 307 passed, 0 failed (see $LOG.integration)"
}
if ! cargo test -p grep-searcher > "$LOG.searcher" 2>&1; then
    tail -30 "$LOG.searcher" >&2
    fail "searcher crate unit suite did not pass (see $LOG.searcher)"
fi
grep -q "test result: ok. 77 passed; 0 failed" "$LOG.searcher" || {
    tail -25 "$LOG.searcher" >&2
    fail "searcher crate unit suite did not report 77 passed, 0 failed (see $LOG.searcher)"
}

# 8) three authored hidden CLI cases: multiple files with a per-file
#    max-count (distinct line sizes per file), UTF-8 multibyte lines, and
#    CRLF line endings - all reaching the same early-stop byte-accounting
#    path from inputs the upstream regression test does not use. Each must
#    exit 0 with the exact expected "N bytes searched" figure.
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

echo "PASS: provenance, fix-unreachable, scope, deliverables, relink, repro both directions (incl. copied pre-fix path), upstream regression test, full integration suite, searcher unit suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0