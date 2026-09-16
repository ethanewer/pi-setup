#!/usr/bin/env bash
# figurehead-grapnel verifier
# binary reward: writes exactly "1" or "0" to /logs/verifier/reward.txt
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
# The agent phase can write into the host-mounted /logs/verifier (it is a
# chmod-777 bind mount shared with the verifier). A stale pre-written
# '1' would survive every verifier failure path because the EXIT trap only
# writes 0 when the file is missing. Wipe any pre-existing reward and start
# from 0 so only the success path below may write 1.
rm -f /logs/verifier/reward.txt
echo 0 > /logs/verifier/reward.txt

REPO=/app/curl
AGENT_BIN="$REPO/src/curl"
BUGGY_BIN=/opt/curl.buggy
GOLDEN=/opt/golden-test804
REPRO=/app/reproduce_bug.sh
PARENT_SHA=81787b0b34c496c46870751f6ca438346036d7a0
FIX_SHA=12cfc836c6fe8f4e4e5001f400d677f0aa530421

echo "== figurehead-grapnel verifier =="

fail() {
    echo "FAIL: $*"
    exit 1
}
pass() {
    echo "PASS: $*"
}

# --- 0. environment sanity ---
[ -x "$REPRO" ] || fail "deliverable $REPRO is missing or not executable"
[ -x "$AGENT_BIN" ] || fail "no curl binary at $AGENT_BIN (deliverable not built)"
[ -x "$BUGGY_BIN" ] || fail "pre-fix reference binary at $BUGGY_BIN is missing"
[ -s "$GOLDEN" ] || fail "canonical golden test at $GOLDEN is missing"
"$AGENT_BIN" --version >/dev/null 2>&1 || fail "agent's curl binary cannot even run"

# --- 1. the fix must live in the project source, not in a swapped binary or a
#        wrapper: require a tracked modification under lib/ or src/ (or a commit
#        on top of the pinned parent), then FORCE a rebuild from source and use
#        its result for every remaining check. ---
if git -C "$REPO" cat-file -e "$FIX_SHA^{commit}" 2>/dev/null; then
    fail "the upstream fix commit object is present in the shipped repository (must be unreachable)"
fi
if [ "$(git -C "$REPO" rev-parse HEAD)" = "$PARENT_SHA" ] \
   && [ -z "$(git -C "$REPO" status --porcelain -- lib src | grep -v '^??')" ]; then
    fail "the source tree at $REPO is untouched (HEAD still at the pinned parent, no tracked changes under lib/ or src/); the bug is still in the code"
fi
# Rebuild from the CURRENT source, not incrementally: clean lib/ first so the
# graded binary provably comes from the source as it stands now. An agent that
# ships a swapped binary or leaves fixed object files behind from an earlier
# edit must have the fix in the source itself or every behavioural check below
# fails.
if ! (cd "$REPO" && make -C lib clean >/dev/null 2>&1 && make -j1 >/tmp/verifier-rebuild.log 2>&1); then
    tail -30 /tmp/verifier-rebuild.log
    fail "the source tree under $REPO does not build (make failed)"
fi
"$AGENT_BIN" --version >/dev/null 2>&1 || fail "rebuilt curl binary does not run"

# --- 2. the agent's own reproduction must FAIL against the pristine pre-fix
#        binary: a reproduction script that does not fail on the unfixed code
#        proves nothing (hardcoded verdicts, ignored binaries etc. die here). ---
if "$REPRO" "$BUGGY_BIN" >/tmp/repro-buggy.log 2>&1; then
    echo "reproduction output against the pre-fix binary:"
    cat /tmp/repro-buggy.log
    fail "the reproduction EXITED 0 against the pre-fix binary; a genuinely failing reproduction was required"
fi
pass "reproduction fails against the pre-fix binary (bug present before the fix)"

# --- 3. ... and must PASS against the agent's rebuilt binary ---
if ! "$REPRO" "$AGENT_BIN" >/tmp/repro-fixed.log 2>&1; then
    echo "reproduction output against the agent's binary:"
    cat /tmp/repro-fixed.log
    fail "the reproduction failed against the agent's rebuilt binary; the bug is still there"
fi
pass "reproduction passes against the agent's rebuilt binary"

# --- 4. the project's own regression test for this behaviour (golden test 804,
#        extracted from the upstream fix commit; the canonical copy overwrites
#        whatever is in the tree, so editing the test cannot help) ---
grep -q "IMAP selects a mailbox when its case changes" "$GOLDEN" || fail "canonical golden test has unexpected content"
cp "$GOLDEN" "$REPO/tests/data/test804"
if ! (cd "$REPO/tests" && timeout 400 ./runtests.pl -n 804 >/tmp/golden-804.log 2>&1); then
    grep -E "test 0804|protocol FAILED|TESTFAIL" /tmp/golden-804.log | head -5
    fail "the project's golden regression test 804 failed against the agent's rebuilt binary"
fi
pass "golden regression test 804 passes via the project's own harness"

# --- 5. enough of the project's own existing suite to show nothing else broke:
#        IMAP tests 800-803, 805, 806 plus basic HTTP tests 1 and 10 ---
if ! (cd "$REPO/tests" && timeout 600 ./runtests.pl -n 1 -n 10 -n 800 -n 801 -n 802 -n 803 -n 805 -n 806 >/tmp/existing-suite.log 2>&1); then
    tail -30 /tmp/existing-suite.log
    fail "an existing project test regressed"
fi
pass "existing project tests still pass (1, 10, 800, 801, 802, 803, 805, 806)"

# --- 6. authored hidden cases exercising the same code path with inputs the
#        golden test does not use ---
#    case 1 (three case-variants) must also FAIL on the pre-fix binary: proof
#    the hidden case genuinely bites.
if python3 /tests/hidden/case-01-three-case-variants/case.py "$BUGGY_BIN" >/tmp/hc01-buggy.log 2>&1; then
    fail "hidden case 1 passed against the pre-fix binary; the case does not bite"
fi
pass "hidden case 1 bites (fails on the pre-fix binary)"

for d in /tests/hidden/case-01-three-case-variants \
         /tests/hidden/case-02-identical-names-reuse \
         /tests/hidden/case-03-inbox-mixed-case; do
    name=$(basename "$d")
    if ! python3 "$d/case.py" "$AGENT_BIN" >/tmp/hc-"$name".log 2>&1; then
        cat /tmp/hc-"$name".log
        fail "hidden case $name failed against the agent's binary"
    fi
    pass "hidden case $name passes"
done

echo 1 > /logs/verifier/reward.txt
echo "REWARD 1"
exit 0