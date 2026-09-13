#!/bin/bash
# Verifier for ballast-anchorage: proves the agent's fix in the real
# BurntSushi/ripgrep tree at /app/src by (1) asserting the verifier's own
# trust anchors (toolchain binaries and the golden regression test still have
# the sha256 pinned at image build time), (2) asserting provenance (HEAD still
# the pinned parent commit; every tracked file except the single replacement
# source file is byte-identical to it; no stray untracked files), (3)
# requiring /app/summary.md, (4) forcing a fresh debug `rg` binary and a fresh
# project test-harness build offline (the artifacts the verifier will execute
# are deleted first so nothing an adversarial agent planted under git-ignored
# target/ can survive), (5) planting the upstream project's own regression
# test for this bug (extracted from the fix commit at image build time into
# /opt/golden, sha256-pinned) and running it, (6) running a targeted selection
# of the project's own multiline/replace integration tests, and (7) running
# four authored hidden CLI cases that reach the same broken replace path from
# inputs the upstream test does not use.
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

PARENT=916415857f084e63efda03cf25a67fe7f6d24244
export PATH=/opt/cargo/bin:$PATH
GIT=/usr/bin/git
CARGO=/opt/cargo/bin/cargo

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the tree, the harness and the
#    golden test; an adversarial agent with write access to /opt (e.g. a root
#    trial) could otherwise swap /opt/cargo/bin/cargo for a stub that reports
#    success for every build, plant a fake integration harness and a fake rg
#    under the git-ignored target/ dir, and earn reward 1 on an untouched tree
#    (proven in independent review before this hardening). The pins recorded
#    at image build time detect any substitution before any build happens.
if ! ( cd / && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1 ) || \
   ! ( cd / && sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 ); then
    fail "toolchain or golden integrity check failed (substituted binary or test)"
fi

# 1) the tree must still be at the pinned parent commit: no commits added,
#    and nothing can hide work from the blob-level scope check below.
if [ "$("$GIT" rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $("$GIT" rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (the replace/capture tail-slice decision in crates/printer/src,
#    discovered by the agent, not named here). This is a CONTENT check, not a
#    git-status check: we hash the actual bytes of every tracked file on disk
#    against the pinned commit's own blob, so assume-unchanged/skip-worktree
#    tricks cannot hide a dirty file, and we refuse any untracked
#    non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        crates/printer/src/util.rs) : ;;
        *)
            want=$("$GIT" rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            # Symlinked tracked files (e.g. HomebrewFormula) must be hashed by
            # their link target, not by following the link.
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

# 3) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) rebuild the debug `rg` from the agent's tree (proves the tree compiles)
#    and plant the upstream regression test (golden bytes, extracted from the
#    fix commit at image build time and sha256-pinned; never part of this task
#    tree) into the test harness, then rebuild the harness offline. The
#    artifacts the verifier is about to execute are deleted first so cargo is
#    forced to produce them from the tree + the pinned golden test; nothing an
#    agent planted under the git-ignored target/ dir survives this.
rm -f target/debug/rg
if ! "$CARGO" build > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cargo build failed on the agent's tree (see $LOG.build)"
fi
cp /opt/golden/regression.rs tests/regression.rs || fail "cannot plant golden regression test"
rm -f target/debug/deps/integration-*
if ! "$CARGO" test --no-run > "$LOG.build2" 2>&1; then
    tail -40 "$LOG.build2" >&2
    fail "cargo test --no-run failed after planting regression test (see $LOG.build2)"
fi

# 5) locate the project's own integration test binary (new cargo layout puts
#    test executables under target/debug/deps/). It must be a real ELF built
#    by the cargo invocation above, not a script planted by the agent.
BIN=""
for b in $(ls -t target/debug/deps/integration-* 2>/dev/null); do
    case "$b" in *.d) continue ;; esac
    BIN=$b; break
done
[ -n "$BIN" ] && [ -x "$BIN" ] || fail "project integration test binary not found"
if [ "$(od -An -tx1 -N4 "$BIN" | tr -d ' \n')" != "7f454c46" ]; then
    fail "integration binary $BIN is not a real ELF executable (planted script?)"
fi

# 6) the upstream regression test must pass. (On the unfixed tree this test
#    fails: rg panics, the child output does not match 'xbxbx\n'.)
if ! "$BIN" r3180_look_around_panic > /tmp/golden.out 2>&1; then
    tail -30 /tmp/golden.out >&2
    fail "upstream regression test for this bug did not pass (see /tmp/golden.out)"
fi
grep -q "regression::r3180_look_around_panic \.\.\. ok" /tmp/golden.out || {
    fail "regression::r3180_look_around_panic did not actually run and pass (see /tmp/golden.out)"
}

# 7) a targeted selection of the project's OWN existing integration tests
#    covering the same machinery (multiline search, replacement, capture
#    groups, only-matching, stdin) must stay green. Every required test must
#    actually have run and passed (a neutralised run would leave no
#    "<name> ... ok" line even though the binary exited 0).
EXISTING="r1311_multi_line_term_replace r2095 r2208 r2480 misc::replace misc::replace_groups misc::replace_named_groups misc::replace_with_only_matching multiline::overlap1 multiline::overlap2 multiline::dot_all multiline::only_matching multiline::stdin multiline::context"
if ! "$BIN" --test-threads 1 $EXISTING > /tmp/existing.out 2>&1; then
    tail -30 /tmp/existing.out >&2
    fail "project's existing multiline/replace tests failed (see /tmp/existing.out)"
fi
for t in r1311_multi_line_term_replace r2095 r2208 r2480 misc::replace misc::replace_groups misc::replace_named_groups misc::replace_with_only_matching multiline::overlap1 multiline::overlap2 multiline::dot_all multiline::only_matching multiline::stdin multiline::context; do
    if ! grep -q "$t \.\.\. ok" /tmp/existing.out; then
        fail "existing test ${t} did not run and pass (see /tmp/existing.out)"
    fi
done

# 8) four authored hidden CLI cases: other inputs/patterns reaching the same
#    replace path. Each must print the byte-exact expected output and exit 0.
#    (Two of them crash the unfixed tree with the slice-index panic; one uses
#    a different pattern; one requires preserving trailing content, which a
#    merely-panic-avoiding clamp gets wrong.)
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"input "$work"/input 2>/dev/null || fail "hidden case $name: missing input"
    cp "$case"expected "$work"/expected || fail "hidden case $name: missing expected"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    ( cd "$work" && bash run.sh > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: rg exited $rc (expected 0); stderr:" >> "$LOG"
        head -8 "$work/stderr.txt" >> "$LOG"
        fail "hidden case $name: rg exited $rc (see $LOG)"
    fi
    if ! cmp -s "$work/stdout.txt" "$work/expected"; then
        echo "hidden case $name: stdout mismatch; got:" >> "$LOG"
        od -c "$work/stdout.txt" | head -8 >> "$LOG"
        fail "hidden case $name: output mismatch (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 4 ] || fail "only $CASES hidden case(s) ran; expected 4"

echo "PASS: provenance, /app/summary.md, build, upstream regression test, existing suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0