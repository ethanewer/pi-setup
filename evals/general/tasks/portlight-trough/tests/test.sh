#!/bin/bash
# Verifier for portlight-trough: proves the agent fixed the serde
# adjacently-tagged-enum-with-extra-keys bug in the real tree at /app/src by
# (1) asserting the verifier's own trust anchors (the golden regression test and
# the toolchain still match their sha256 recorded at image build time),
# (2) asserting provenance (HEAD still the pinned parent commit; the upstream fix
# commit is not reachable from this object store), (3) a content-level scope check
# that every tracked file except the two source files a correct fix lives in is
# byte-identical to the parent commit, and no stray untracked files,
# (4) requiring the two deliverables /app/repro.rs and /app/summary.md,
# (5) a CLEAN rebuild of the agent's tree (target wiped, so nothing planted can
# survive) followed by replanting the golden regression test and running the
# project's own test binaries test_macros/test_ser/test_de/test_annotations/
# test_value/test_gen/test_borrow - all must pass,
# (6) running the agent's own reproduction against the repaired tree (must pass)
# and against a pristine pre-fix copy of the parent reconstructed from the object
# store with `git archive` (must fail - proving the symptom is real and the
# reproduction targets it), and (7) running three authored hidden cases that reach
# the same code path from inputs the upstream test does not use (heterogeneous
# skipped extras; deny_unknown_fields honored; and h3, whose tag/content and extra
# key names are generated at verifier time with $RANDOM so no readable file can
# be enumerated to hardcode the sampled inputs).
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

PARENT=c96efcb87ab72f14a2a084644308c4a5e98ed820
FIX=873cfbe9ab4271ce1bd30c0b0bbfdfaed652ccf8

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors. The golden regression test and the rust toolchain are
#    pinned by sha256 at image build time; a non-root trial can write the
#    world-writable /opt/cargo and /opt/rustup but not the root-owned 0555
#    /opt/pins file, so substituting either would be caught here.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/toolchain.sha256 >/dev/null 2>&1; then
    fail "golden or toolchain integrity check failed (substituted file)"
fi

# 1) provenance: still detached at the pinned parent commit, and the upstream
#    fix commit is not reachable from this object store (no fetch/graft).
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# 2) scope: a correct fix to this bug lives in serde_derive/src/de.rs (the
#    generated code) and serde/src/private/de.rs (the field visitor helpers).
#    Everything else must be byte-identical to the pinned parent commit, and the
#    working tree must hold no stray untracked non-ignored files (the agent's
#    reproduction lives at /app/repro.rs, outside the repo).
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        serde/src/private/de.rs|serde_derive/src/de.rs) : ;;  # the bug's files
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            # Index mode decides how the entry is materialised. Serde ships
            # symlinks (mode 120000) for sub-crate LICENSE/README -> ../; a
            # plain `git hash-object` would follow the link and hash the
            # target's content, so hash the link target itself. Gitlinks
            # (mode 160000) are never materialised and are skipped.
            mode=$(git ls-files -s -- "$f" | awk '{print $1}')
            case "$mode" in
                160000*) continue ;;
                120000*)
                    have=$(printf '%s' "$(readlink "$f")" | git hash-object --stdin 2>/dev/null || true)
                    ;;
                *)
                    have=$(git hash-object -- "$f" 2>/dev/null || true)
                    ;;
            esac
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "tracked file differs from parent: $f (mode $mode)" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file in /app/src: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG" >&2
    fail "working tree modified outside the bug's source files (see $LOG)"
fi

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -s /app/repro.rs ] || fail "/app/repro.rs is missing or empty"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) clean rebuild of the agent's tree, replant the golden regression test, and
#    run the project's own test binaries. Wiping target means every executed
#    binary is provably rebuilt from the tree's sources (nothing planted
#    survives). The golden test is the fix commit's test_macros.rs, which appends
#    the extra-keys assertion to test_adjacently_tagged_enum; replanting it over
#    the tree copy and running it exercises both the new regression and all the
#    previously-existing test_macros assertions.
rm -rf target || fail "cannot remove target"
cp /opt/golden/test_macros.rs test_suite/tests/test_macros.rs || fail "cannot plant golden test"
for suite in test_macros test_ser test_de test_annotations test_value test_gen test_borrow; do
    if ! cargo test -p serde_test_suite --test "$suite" > "$LOG.$suite" 2>&1; then
        tail -25 "$LOG.$suite" >&2
        fail "$suite did not pass on the fixed tree (see $LOG.$suite)"
    fi
    grep -q "test result: ok" "$LOG.$suite" || {
        tail -20 "$LOG.$suite" >&2
        fail "$suite did not report a passing run (see $LOG.$suite)"
    }
done
# Explicitly confirm the upstream regression assertion itself ran and passed.
grep -q "test result: ok" "$LOG.test_macros" || fail "test_macros did not pass"

# 5) the agent's reproduction, both directions. Against the repaired tree it
#    must pass; against a pristine pre-fix copy reconstructed from the object
#    store it must fail.
cp /app/repro.rs test_suite/tests/repro_custom.rs
if ! cargo test -p serde_test_suite --test repro_custom > "$LOG.repro-fixed" 2>&1; then
    tail -25 "$LOG.repro-fixed" >&2
    fail "agent repro errored on the repaired tree (see $LOG.repro-fixed)"
fi
grep -q "test result: ok" "$LOG.repro-fixed" || fail "agent repro did not report ok on the repaired tree"

rm -rf /tmp/pre && mkdir -p /tmp/pre || fail "cannot create pre-fix scratch dir"
git archive --format=tar HEAD | tar -x -C /tmp/pre || fail "pre-fix archive extraction failed"
cp /app/repro.rs /tmp/pre/test_suite/tests/repro_custom.rs
( cd /tmp/pre && rm -rf target && cargo test -p serde_test_suite --test repro_custom > /tmp/pre.out 2>&1 )
rc=$?
if [ "$rc" -eq 0 ]; then
    tail -20 /tmp/pre.out >&2
    fail "agent repro PASSED on the pre-fix tree - the reproduction is not genuine"
fi

# 6) authored hidden cases over the same code path, from inputs the upstream
#    test does not use.
CASES=0
for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    name=$(basename "$case")
    rm -rf "/tmp/hc-$name"; mkdir -p "/tmp/hc-$name"
    if ! bash "$case/run.sh" > "$LOG.hc-$name" 2>&1; then
        tail -25 "$LOG.hc-$name" >&2
        fail "hidden case $name did not pass (see $LOG.hc-$name)"
    fi
    CASES=$((CASES+1))
done
[ "$CASES" -ge 2 ] || fail "fewer than 2 hidden cases ran"

echo "ALL CHECKS PASSED"
echo "1" > /logs/verifier/reward.txt
exit 0
