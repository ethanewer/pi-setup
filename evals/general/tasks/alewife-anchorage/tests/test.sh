#!/bin/bash
# Verifier for alewife-anchorage: proves the agent's fix in the real
# BurntSushi/ripgrep tree at /app/src by (1) asserting the verifier's own
# trust anchors (toolchain binaries, the golden regression test and the
# pre-fix binary still have the sha256 pinned at image build time), (2)
# asserting provenance (HEAD still the pinned parent commit; every tracked
# file except the single replacement source file is byte-identical to it;
# no stray untracked files), (3) requiring /app/repro.sh and /app/summary.md,
# (4) forcing a fresh debug `rg` binary build offline (the artifact the
# verifier executes is deleted first so nothing an adversarial agent planted
# under git-ignored target/ can survive), (5) running the agent's own
# reproduction against the repaired binary (must pass) and against a
# pristine pre-fix binary baked at /opt/prefix/rg (must fail - this proves
# the symptom is real and the reproduction targets it), (6) planting the
# upstream project's own regression test for this bug (extracted from the
# fix commit at image build time into /opt/golden, sha256-pinned) and
# running it, (7) running a targeted selection of the project's own
# ignore/whitelist integration tests, and (8) running four authored hidden
# CLI cases that reach the same broken ignore-walker path from inputs the
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

PARENT=bb88a1ac45c70bef97e0d6ccd6e91595610de860
export PATH=/opt/cargo/bin:$PATH
GIT=/usr/bin/git
CARGO=/opt/cargo/bin/cargo

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The verifier executes the tree, the harness, the
#    golden test and the pre-fix binary; an adversarial agent with write
#    access to /opt (e.g. a root trial) could otherwise swap
#    /opt/cargo/bin/cargo for a stub that reports success for every build,
#    replace /opt/prefix/rg with a binary that reproduces the bug (so the
#    pre-fix direction check fails to fail), or tamper with the golden test,
#    and earn reward 1 on an untouched tree. The pins recorded at image
#    build time detect any substitution before anything is executed.
if ! ( cd / && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1 ) || \
   ! ( cd / && sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 ) || \
   ! ( cd / && sha256sum -c /opt/pins/prefix-rg.sha256 >/dev/null 2>&1 ); then
    fail "toolchain, golden or prefix-binary integrity check failed (substituted file)"
fi

# 1) the tree must still be at the pinned parent commit: no commits added,
#    and nothing can hide work from the blob-level scope check below.
if [ "$("$GIT" rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $("$GIT" rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug
#    lives in (the ancestor-ignore walker decision in crates/ignore,
#    discovered by the agent, not named here). This is a CONTENT check, not
#    a git-status check: we hash the actual bytes of every tracked file on
#    disk against the pinned commit's own blob, so assume-unchanged /
#    skip-worktree tricks cannot hide a dirty file, and we refuse any
#    untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        crates/ignore/src/dir.rs) : ;;
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

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) rebuild the debug `rg` from the agent's tree (proves the tree
#    compiles). The artifact the verifier is about to execute is deleted
#    first so cargo is forced to produce it from the tree; nothing an agent
#    planted under the git-ignored target/ dir survives this.
rm -f target/debug/rg
if ! "$CARGO" build > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cargo build failed on the agent's tree (see $LOG.build)"
fi

# 5) the agent's reproduction, both directions. Against the repaired binary
#    it must pass - exit 0 AND the whitelisted hidden file listed. Against
#    the pristine pre-fix binary baked into the image it must fail - any
#    exit 0 there means the reproduction is fake/hardcoded or the symptom is
#    not what we think it is.
if ! bash /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
if ! grep -q '\.' /tmp/repro_fixed.out || [ ! -s /tmp/repro_fixed.out ]; then
    fail "agent repro printed no file listing on the repaired tree"
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
#    task tree) into the test harness, then rebuild the harness offline.
#    The integration artifacts are deleted first so cargo is forced to
#    rebuild them from the tree + the pinned golden test.
cp /opt/golden/regression.rs tests/regression.rs || fail "cannot plant golden regression test"
rm -f target/debug/deps/integration-*
if ! "$CARGO" test --no-run > "$LOG.build2" 2>&1; then
    tail -40 "$LOG.build2" >&2
    fail "cargo test --no-run failed after planting regression test (see $LOG.build2)"
fi

# 7) locate the project's own integration test binary (new cargo layout puts
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

# 8) the upstream regression test must pass. (On the unfixed tree this test
#    fails: `rg --files .` from the subdir prints nothing.)
if ! "$BIN" r3173_hidden_whitelist_only_dot > /tmp/golden.out 2>&1; then
    tail -30 /tmp/golden.out >&2
    fail "upstream regression test for this bug did not pass (see /tmp/golden.out)"
fi
grep -q "regression::r3173_hidden_whitelist_only_dot \.\.\. ok" /tmp/golden.out || {
    fail "regression::r3173_hidden_whitelist_only_dot did not actually run and pass (see /tmp/golden.out)"
}

# 9) a targeted selection of the project's OWN existing integration tests
#    covering the same machinery (ignore files, whitelist negation, ignore
#    flags, hidden-file handling) must stay green. Every required test must
#    actually have run and passed (a neutralised run would leave no
#    "<name> ... ok" line even though the binary exited 0).
EXISTING="r2711 r807 r829_original r829_2731 r829_2747 r829_2778 f68_no_ignore_vcs f1138_no_ignore_dot f1207_ignore_encoding f1404_nothing_searched_ignored f1420_no_ignore_exclude f1466_no_ignore_files"
if ! "$BIN" --test-threads 1 $EXISTING > /tmp/existing.out 2>&1; then
    tail -30 /tmp/existing.out >&2
    fail "project's existing ignore/whitelist tests failed (see /tmp/existing.out)"
fi
for t in $EXISTING; do
    if ! grep -q "$t \.\.\. ok" /tmp/existing.out; then
        fail "existing test ${t} did not run and pass (see /tmp/existing.out)"
    fi
done

# 10) four authored hidden CLI cases: other hidden names, other whitelist
#     patterns, deeper nesting, and a hidden directory - all reaching the
#     same ancestor-ignore walker path from inputs the upstream test does
#     not use. Each must print the byte-exact expected listing and exit 0.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    cp "$case"expected "$work"/expected || fail "hidden case $name: missing expected"
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

echo "PASS: provenance, deliverables, build, repro both directions, upstream regression test, existing suite, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0