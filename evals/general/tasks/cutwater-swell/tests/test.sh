#!/bin/bash
# Verifier for cutwater-swell: proves the agent's fix in the real
# BurntSushi/ripgrep tree at /app/src by (1) asserting the verifier's own
# trust anchors (the golden regression test and the pre-fix binary still
# have the sha256 pinned at image build time), (2) asserting provenance
# (HEAD still the pinned parent commit; the upstream fix commit is not
# reachable from this clone; every tracked file except the single source
# file the bug lives in is byte-identical to the parent commit; no stray
# untracked files), (3) requiring /app/repro.sh and /app/summary.md,
# (4) forcing a CLEAN rebuild from the source tree (`cargo clean` then
# `cargo build`, so nothing the agent planted under the git-ignored target/
# output can survive and the executed binary is provably built from the
# agent's sources), (5) running the agent's own reproduction against the
# repaired binary (must pass) and against a pristine pre-fix binary baked at
# /opt/prefix/rg (must fail - the reproduction targets the real symptom),
# (6) planting the upstream project's own regression test for this bug
# (case_insensitive_alternation, extracted from the fix commit at image
# build time into /opt/golden, sha256-pinned) inside the tests module of
# the agent's literal.rs and running it plus the whole grep-regex unit
# suite, and (7) running three authored hidden CLI cases that reach the
# same inner-literal-extraction search path from inputs the upstream test
# does not use.
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

PARENT=6c5108ed17987531644518fac8c1659b0b202611
FIX=9d738ad0c009e6632d75fa3d36051e5ae7f7cce6
export PATH=/opt/rust/bin:$PATH CARGO_NET_OFFLINE=true

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the tree, the golden test, the
#    pre-fix binary and (via cargo) the toolchain; an adversarial agent with
#    write access to /opt or /usr (e.g. a root trial) could otherwise
#    replace /opt/prefix/rg with a binary that reproduces no bug (so the
#    pre-fix direction check fails to fail), tamper with the golden test, or
#    swap the compiler for a stub that fakes a green run. The pins recorded
#    at image build time detect any substitution before anything is
#    executed.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/prefix-rg.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden, pre-fix binary or toolchain integrity check failed (substituted file)"
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
#    check, not a git-status check: the actual bytes of every tracked file
#    on disk are hashed against the pinned commit's own blob, so
#    assume-unchanged / skip-worktree tricks cannot hide a dirty file, and
#    any untracked non-ignored file is refused.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        crates/regex/src/literal.rs) : ;;  # the one source file the bug lives in
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            # Index oid first: authoritative for gitlink (submodule) entries.
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
    fail "working tree modified outside crates/regex/src/literal.rs (see $LOG)"
fi

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) clean rebuild from the agent's sources. Everything the verifier is
#    about to execute is thrown away first (cargo clean), so the binary
#    comes from the tree as delivered; a planted prebuilt binary or object
#    file cannot survive, and a tree that does not compile fails here.
if ! cargo clean > "$LOG.clean" 2>&1; then
    tail -20 "$LOG.clean" >&2
    fail "cargo clean failed (see $LOG.clean)"
fi
if ! cargo build > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cargo build failed on the agent's tree (see $LOG.build)"
fi
[ -x /app/src/target/debug/rg ] || fail "/app/src/target/debug/rg not produced by the rebuild"
if [ "$(od -An -tx1 -N4 /app/src/target/debug/rg | tr -d ' \n')" != "7f454c46" ]; then
    fail "/app/src/target/debug/rg is not a real ELF executable (planted wrapper?)"
fi

# 5) the agent's reproduction, both directions. Against the repaired binary
#    it must pass; against the pristine pre-fix binary it must fail. The
#    pre-fix binary itself must first prove it is the real, executable,
#    bug-bearing tree binary: an unexecutable file (chmod trick, same sha256)
#    would make the "must fail" direction vacuous, and a swapped-in stub is
#    caught by the sha256 pin. So: (a) it must be executable, (b) it must
#    perform an ordinary search correctly (real binary, not a stub), and
#    (c) it must still exhibit the defect on the triggering pattern. Only
#    then is "repro must fail against it" meaningful.
if [ ! -x /opt/prefix/rg ]; then
    fail "/opt/prefix/rg is not executable"
fi
printf 'box\n' | /opt/prefix/rg -c box - > /tmp/prefix_smoke.out 2>&1
rc=$?
if [ "$rc" -ne 0 ] || [ "$(cat /tmp/prefix_smoke.out)" != "1" ]; then
    fail "pre-fix binary failed an ordinary search smoke test (c=$rc out=$(cat /tmp/prefix_smoke.out))"
fi
printf 'e-x\n' | /opt/prefix/rg -c '(?i:e.x|ex)' - > /tmp/prefix_bug.out 2>&1
rc=$?
if [ "$rc" -eq 0 ] || [ -s /tmp/prefix_bug.out ]; then
    fail "pre-fix binary does not reproduce the defect (bug-echo test failed)"
fi
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

# 6) plant the upstream regression test (golden bytes, extracted from the
#    fix commit at image build time and sha256-pinned; never part of this
#    task tree) inside the tests module of the agent's fixed literal.rs.
python3 /tests/plant_golden.py >> "$LOG" 2>&1 || fail "planting the golden regression test failed"

# 7) the upstream regression test, and the whole grep-regex unit suite.
if ! cargo test -p grep-regex --lib case_insensitive_alternation > "$LOG.golden" 2>&1; then
    tail -30 "$LOG.golden" >&2
    fail "golden regression test case_insensitive_alternation did not pass (see $LOG.golden)"
fi
grep -q "case_insensitive_alternation ... ok" "$LOG.golden" || {
    tail -20 "$LOG.golden" >&2
    fail "the golden regression test did not actually run and pass (see $LOG.golden)"
}
if ! cargo test -p grep-regex --lib > "$LOG.suite" 2>&1; then
    tail -40 "$LOG.suite" >&2
    fail "cargo test -p grep-regex --lib did not pass on the repaired tree (see $LOG.suite)"
fi
grep -q "test result: ok" "$LOG.suite" || {
    tail -20 "$LOG.suite" >&2
    fail "grep-regex unit suite did not report a passing run (see $LOG.suite)"
}
grep -q "0 failed" "$LOG.suite" || {
    tail -20 "$LOG.suite" >&2
    fail "grep-regex unit suite reported failures (see $LOG.suite)"
}
# The full suite must contain exactly the 24 pre-existing tests plus the
# golden regression test. Any other total means the agent deleted or skipped
# a failing test to make the suite green, or did not keep the suite intact.
if ! grep -q "25 passed" "$LOG.suite"; then
    tail -25 "$LOG.suite" >&2
    fail "grep-regex unit suite did not run all 25 tests (test deleted/skipped? see $LOG.suite)"
fi
grep -q "case_insensitive_alternation" "$LOG.suite" || {
    tail -20 "$LOG.suite" >&2
    fail "golden regression test missing from the full suite output (see $LOG.suite)"
}

# 8) three authored hidden CLI cases: a different alphabet (t.t|tt), an
#    exact rg -c line count over a large mixed-case / mid-line input, and a
#    two-character gap with case variants and a single-gap decoy - all
#    reaching the same inner-literal-extraction search path from inputs the
#    upstream regression test does not use. Each must exit 0.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    ( cd "$work" && RG_BIN=/app/src/target/debug/rg bash run.sh > stdout.txt 2> stderr.txt )
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

echo "PASS: provenance, fix-unreachable, scope, deliverables, clean rebuild, repro both directions, golden regression test, existing unit suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0