#!/bin/bash
# Verifier for capstan-drift: proves the agent's fix in the real
# Mbed-TLS tree at /app/src by (1) asserting provenance (HEAD still the
# pinned parent commit, submodules at their pinned commits, every tracked
# file except library/pkcs7.c byte-identical to the parent blobs, no stray
# untracked files, the fixture .der files untouched), (2) requiring
# /app/summary.md, (3) planting the project's OWN regression test for this
# bug (extracted from the fix commit at image build time into /opt/golden)
# and rebuilding the project's own machinery, (4) running the full pkcs7
# test suite (must print PASSED 815/815 including the reuse case) and the
# project's x509parse suite (888/888), and (5) running three authored hidden
# programs that drive the same object-reuse code path with inputs and cycle
# depths the upstream regression test does not use, asserting real parsed
# content afterwards -- so merely avoiding the abort is not enough.
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

PARENT=5ca2218a28a49cfdcc8cebe8953f6cb07bf7084f
FRAMEWORK_SHA=e92a81996656d82941a9afce843453c57e1d51f5
PSA_SHA=93fa04691f6d5628f51a369953856bf5bf75d31f

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit: no commits added,
#    and nothing can hide work from the blob-level scope check below.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) submodules must be at their pinned commits and clean; the certificate
#    fixture files the hidden cases read must be byte-identical to the blobs
#    pinned by the framework submodule (tampering with fixtures is out of
#    scope and would invalidate the hidden cases).
if [ "$(git -C framework rev-parse HEAD)" != "$FRAMEWORK_SHA" ]; then
    fail "framework submodule HEAD is $(git -C framework rev-parse HEAD), expected $FRAMEWORK_SHA"
fi
if [ "$(git -C tf-psa-crypto rev-parse HEAD)" != "$PSA_SHA" ]; then
    fail "tf-psa-crypto submodule HEAD is $(git -C tf-psa-crypto rev-parse HEAD), expected $PSA_SHA"
fi
if [ "$(git -C tf-psa-crypto/framework rev-parse HEAD)" != "$FRAMEWORK_SHA" ]; then
    fail "tf-psa-crypto/framework submodule HEAD is $(git -C tf-psa-crypto/framework rev-parse HEAD), expected $FRAMEWORK_SHA"
fi
if [ -n "$(git -C framework status --porcelain)" ]; then
    fail "framework submodule has uncommitted changes"
fi
if [ -n "$(git -C tf-psa-crypto status --porcelain)" ]; then
    fail "tf-psa-crypto submodule has uncommitted changes"
fi

# 3) scope: every change must live in exactly the one library source file
#    the bug is in (the PKCS#7 parse/cleanup lifecycle, discovered by the
#    agent, not named here). CONTENT check: hash the actual bytes of every
#    tracked file on disk against the pinned commit's own blob, and refuse
#    any untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        library/pkcs7.c) : ;;
        framework|tf-psa-crypto) : ;;   # gitlinks; contents checked in (2)
        *)
            t=$(git cat-file -t "$PARENT:$f" 2>/dev/null || true)
            [ "$t" = "blob" ] || continue
            want=$(git rev-parse "$PARENT:$f")
            if [ -L "$f" ]; then
                have=$(printf '%s' "$(readlink "$f")" | git hash-object --stdin 2>/dev/null || true)
            else
                have=$(git hash-object -- "$f" 2>/dev/null || true)
            fi
            if [ -z "$have" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
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

# 4) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 5a) the golden bytes must be exactly the byte strings extracted from the
#    fix commit at image build time. These expected checksums live in this
#    file, which is on the harness-owned /tests mount and cannot be forged
#    from inside the trial container, so an agent that tampered with
#    /opt/golden (to drop or neuter the reuse case) is caught here.
WANT_GOLDEN_DATA=cf5e8fd6f0bb54e1a1c9b1562ebca988e7fbaec08fe2537b9af31a75c38de578
WANT_GOLDEN_FUNC=4ac25d03af48ee16bea574e5402ef2e7adc64e6a654a138613c849edb31f20c9
[ "$(sha256sum /opt/golden/test_suite_pkcs7.data | cut -d' ' -f1)" = "$WANT_GOLDEN_DATA" ] || fail "/opt/golden/test_suite_pkcs7.data does not match the fix-commit byte string"
[ "$(sha256sum /opt/golden/test_suite_pkcs7.function | cut -d' ' -f1)" = "$WANT_GOLDEN_FUNC" ] || fail "/opt/golden/test_suite_pkcs7.function does not match the fix-commit byte string"

# 5b) plant the upstream regression test (golden bytes, extracted from the
#    fix commit at image build time; never part of this task tree) and
#    rebuild the project's own machinery from the agent's tree, offline.
cp /opt/golden/test_suite_pkcs7.data tests/suites/test_suite_pkcs7.data || fail "cannot plant golden .data"
cp /opt/golden/test_suite_pkcs7.function tests/suites/test_suite_pkcs7.function || fail "cannot plant golden .function"

# 5c) force the library to be rebuilt from the bytes actually in the working
#    tree, not from anything an agent left in the gitignored build/ dir.
#    Without this, an agent could apply the real fix, build, restore the
#    buggy source with an old mtime, and leave the fixed .a in place: the
#    suite would then pass while the checked-in source still contains the
#    bug. Touching the bug's source file makes make regenerate its object
#    from the true tree, so the planted test runs against the real code.
touch library/pkcs7.c
if ! cmake --build build --target test_suite_pkcs7 -j1 > "$LOG.build" 2>&1; then
    tail -40 "$LOG.build" >&2
    fail "cmake --build test_suite_pkcs7 failed on the agent's tree (see $LOG.build)"
fi

# 6) the project's OWN pkcs7 suite, now including the upstream regression
#    test for this bug, must pass in full. On the unfixed tree the reuse
#    case aborts the whole suite: 'free(): double free detected in tcache 2',
#    exit 134, so the suite never prints the PASSED line.
if ! ./build/tests/test_suite_pkcs7 > /tmp/golden.out 2>&1; then
    tail -25 /tmp/golden.out >&2
    fail "pkcs7 suite did not pass on the agent's tree (see /tmp/golden.out; on the unfixed tree the reuse case aborts with a double free)"
fi
if ! grep -q "PASSED (815 / 815 tests (5 skipped))" /tmp/golden.out; then
    tail -10 /tmp/golden.out >&2
    fail "pkcs7 suite did not print PASSED (815 / 815 tests (5 skipped)) (see /tmp/golden.out)"
fi
if ! grep -E "PKCS7 Signed Data Parse reused object after multiple signers .*PASS" /tmp/golden.out > /dev/null; then
    tail -10 /tmp/golden.out >&2
    fail "the reuse regression case 'PKCS7 Signed Data Parse reused object after multiple signers' did not run and pass (see /tmp/golden.out)"
fi

# 7) the project's x509parse suite (pkcs7 embeds certificate parsing) must
#    still pass: the fix must not have broken anything else.
if ! cmake --build build --target test_suite_x509parse -j1 > "$LOG.build2" 2>&1; then
    tail -30 "$LOG.build2" >&2
    fail "cmake --build test_suite_x509parse failed on the agent's tree (see $LOG.build2)"
fi
if ! ./build/tests/test_suite_x509parse > /tmp/x509.out 2>&1; then
    tail -15 /tmp/x509.out >&2
    fail "x509parse suite did not pass on the agent's tree (see /tmp/x509.out)"
fi
if ! grep -q "PASSED (888 / 888 tests (58 skipped))" /tmp/x509.out; then
    tail -10 /tmp/x509.out >&2
    fail "x509parse suite did not print PASSED (888 / 888 tests (58 skipped)) (see /tmp/x509.out)"
fi

# 8) three authored hidden programs driving the same object-reuse code path
#    from inputs the upstream regression test does not use. Each is compiled
#    against the library rebuilt above and must print its exact expected
#    line and exit 0. The hidden inputs include a hand-authored zero-signer
#    message, deeper cycles (four parses), a rejected message between two
#    valid parses, and single-signer shapes; a fix that merely avoids the
#    abort (e.g. nulling one list pointer) fails the stale-state assertions.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    work=/tmp/hc-$name
    rm -rf "$work"; mkdir -p "$work"
    cp "$case"run.sh "$work"/run.sh || fail "hidden case $name: missing run.sh"
    cp "$case"hc*.c "$work"/ 2>/dev/null || fail "hidden case $name: missing C source"
    cp "$case"expected "$work"/expected || fail "hidden case $name: missing expected"
    ( cd "$work" && bash run.sh > stdout.txt 2> stderr.txt )
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: exited $rc (expected 0); stderr:" >> "$LOG"
        head -12 "$work/stderr.txt" >> "$LOG"
        fail "hidden case $name: exited $rc (see $LOG)"
    fi
    if ! cmp -s "$work/stdout.txt" "$work/expected"; then
        echo "hidden case $name: stdout mismatch; got:" >> "$LOG"
        od -c "$work/stdout.txt" | head -6 >> "$LOG"
        fail "hidden case $name: output mismatch (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected 3"

echo "PASS: provenance, /app/summary.md, build, upstream regression test, project suites, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0