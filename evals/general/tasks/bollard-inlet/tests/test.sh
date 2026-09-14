#!/bin/bash
# Verifier for bollard-inlet (syncthing/syncthing #10785): proves the
# agent's fix in the real tree at /app/src by (0) checking sha256 pins of
# the toolchain and the golden regression test, (1) asserting HEAD is still
# the pinned parent commit, (2) requiring /app/repro.sh and /app/summary.md,
# (3) planting the upstream regression test (extracted from the fix commit
# at image build time into /opt/golden) into the repaired tree and running
# it - it must pass; (4) running the same golden test against the pristine
# pre-fix tree baked at /opt/prefix-src - it must fail with the reported
# "too many levels of symbolic links" diagnostic; (5) running the agent's
# own reproduction against the repaired tree (must pass) and against the
# pre-fix tree (must fail with the diagnostic); (6) running the project's
# own full lib/ignore and lib/fs suites with the planted golden test and
# three authored hidden cases (symlink target in a subdirectory, symlink
# target outside the folder via "..", and the OptFollow open flag tested
# directly in lib/fs) - everything must pass.
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

PARENT=d4cffd848eb13d65f3caca5ef6da9a3fd25a2d6a
GO=/usr/local/go/bin/go
GIT=/usr/bin/git
DIAG="too many levels of symbolic links"

# 0) trust anchors. The verifier executes the go binary, git and the golden
#    test; a substituted or flushed toolchain/golden must be detected before
#    anything is executed. (The pins were recorded at image build time.)
GOLDEN_SHA_LITERAL=b8456102dccdcefaa68f7fb5350de8af2a2617d02e7d88848779e95654c32ad1
if ! ( cd / && sha256sum -c /opt/pins/pins.sha256 > /dev/null 2>&1 ); then
    fail "toolchain/golden integrity check failed (substituted file)"
fi
if [ "$(sha256sum /opt/golden/ignore_test.go | cut -d' ' -f1)" != "$GOLDEN_SHA_LITERAL" ]; then
    fail "/opt/golden/ignore_test.go does not match the pinned upstream bytes"
fi
# The pre-fix concept tree must still carry the exact golden test bytes.
GOLDEN_SHA=$(awk '$2 == "/opt/golden/ignore_test.go" { print $1 }' /opt/pins/pins.sha256)
if [ "$GOLDEN_SHA" != "$GOLDEN_SHA_LITERAL" ] || \
   [ "$(sha256sum /opt/prefix-src/lib/ignore/ignore_test.go | cut -d' ' -f1)" != "$GOLDEN_SHA_LITERAL" ]; then
    fail "pre-fix tree does not carry the pinned golden test"
fi

# 1) the trial tree must still sit exactly on the pinned parent commit.
cd /app/src || fail "/app/src is missing"
if [ "$("$GIT" rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $("$GIT" rev-parse HEAD), expected pinned parent $PARENT"
fi

# 2) deliverables.
[ -x /app/repro.sh ] || fail "/app/repro.sh is missing or not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
grep -qi "symlink" /app/summary.md || fail "/app/summary.md does not mention the symlink root cause"

# 3) clear any scratch test files the agent left in the tree, plant the
#    upstream regression test for this bug (golden) into the repaired tree.
"$GIT" clean -fdq -- lib/ignore lib/fs
cp /opt/golden/ignore_test.go lib/ignore/ignore_test.go || fail "cannot plant golden test into lib/ignore"

# 4) golden test on the REPAIRED tree: must run and pass.
(cd /app/src && timeout 900 "$GO" test ./lib/ignore/ -run "TestIgnoreThroughSymlink" -v) > /tmp/golden_fixed.out 2>&1
rc=$?
if [ $rc -ne 0 ] || ! grep -q -- "--- PASS: TestIgnoreThroughSymlink" /tmp/golden_fixed.out; then
    echo "golden test failed on the repaired tree; tail:" >> "$LOG"
    tail -15 /tmp/golden_fixed.out >> "$LOG"
    fail "upstream regression test TestIgnoreThroughSymlink did not pass on the repaired tree"
fi

# 5) golden test on the pristine PRE-FIX tree (baked at /opt/prefix-src):
#    must FAIL and the failure must be the reported diagnostic. This proves
#    the exact symptom is still reproducible in this image with these
#    pinned toolchain/caches, i.e. it is the same bug the fix must address.
(cd /opt/prefix-src && timeout 900 "$GO" test ./lib/ignore/ -run "TestIgnoreThroughSymlink" -v) > /tmp/golden_prefix.out 2>&1
rc=$?
if [ $rc -eq 0 ] || ! grep -q -- "--- FAIL: TestIgnoreThroughSymlink" /tmp/golden_prefix.out || ! grep -q "$DIAG" /tmp/golden_prefix.out; then
    echo "golden test did not fail with the reported diagnostic on the pre-fix tree; tail:" >> "$LOG"
    tail -15 /tmp/golden_prefix.out >> "$LOG"
    fail "pre-fix concept check did not reproduce the reported symptom"
fi

# 6) the agent's OWN reproduction against the repaired tree: exit 0 and
#    print evidence that rules load through the symlink.
bash /app/repro.sh /app/src > /tmp/repro_fixed.out 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -15 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree"
fi
if ! grep -qi "pass" /tmp/repro_fixed.out; then
    fail "agent repro printed no success evidence on the repaired tree"
fi

# 7) the agent's OWN reproduction against the pristine pre-fix tree: must
#    FAIL, and print the reported diagnostic (a vacuous or hardcoded
#    reproduction cannot satisfy this).
bash /app/repro.sh /opt/prefix-src > /tmp/repro_prefix.out 2>&1
rc=$?
if [ $rc -eq 0 ]; then
    echo "agent repro passed on the pre-fix tree (expected failure); stdout:" >> "$LOG"
    head -15 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree"
fi
if ! grep -q "$DIAG" /tmp/repro_prefix.out; then
    echo "agent repro failed without the reported diagnostic; stdout:" >> "$LOG"
    head -15 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not demonstrate the reported symptom on the pre-fix tree"
fi

# 8) plant the three authored hidden cases:
#    - lib/ignore: symlink whose TARGET lives in a subdirectory,
#    - lib/ignore: symlink whose TARGET is outside the folder (".." link),
#    - lib/fs:     the new OptFollow open flag tested directly.
cp /tests/hidden/subdir_target/hidden_subdir_target_test.go lib/ignore/hidden_subdir_target_test.go \
    || fail "missing hidden case subdir_target"
cp /tests/hidden/outside_target/hidden_outside_target_test.go lib/ignore/hidden_outside_target_test.go \
    || fail "missing hidden case outside_target"
cp /tests/hidden/optfollow/hidden_optfollow_test.go lib/fs/hidden_optfollow_test.go \
    || fail "missing hidden case optfollow"

# 9) the project's OWN lib/ignore suite (existing tests + planted golden +
#    hidden cases) must be green, with the golden and hidden tests actually
#    running and passing.
(cd /app/src && timeout 1200 "$GO" test ./lib/ignore/ -v) > /tmp/suite_ignore.out 2>&1
rc=$?
if [ $rc -ne 0 ] || grep -q -- "--- FAIL:" /tmp/suite_ignore.out || ! grep -qE "^ok" /tmp/suite_ignore.out; then
    echo "lib/ignore suite failed; tail:" >> "$LOG"
    tail -25 /tmp/suite_ignore.out >> "$LOG"
    fail "project lib/ignore suite failed (see $LOG)"
fi
for t in TestIgnoreThroughSymlink TestHiddenStignoreSymlinkTargetInSubdir TestHiddenStignoreSymlinkTargetOutsideFolder; do
    if ! grep -q -- "--- PASS: $t" /tmp/suite_ignore.out; then
        fail "expected test $t did not run and pass in the lib/ignore suite"
    fi
done

# 10) the project's OWN lib/fs suite (the layer the fix's flag plumbing
#     lives in) + the hidden OptFollow case must be green too.
(cd /app/src && timeout 1200 "$GO" test ./lib/fs/ -v) > /tmp/suite_fs.out 2>&1
rc=$?
if [ $rc -ne 0 ] || grep -q -- "--- FAIL:" /tmp/suite_fs.out || ! grep -qE "^ok" /tmp/suite_fs.out; then
    echo "lib/fs suite failed; tail:" >> "$LOG"
    tail -25 /tmp/suite_fs.out >> "$LOG"
    fail "project lib/fs suite failed (see $LOG)"
fi
if ! grep -q -- "--- PASS: TestHiddenOptFollowOpensSymlink" /tmp/suite_fs.out; then
    fail "hidden case TestHiddenOptFollowOpensSymlink did not run and pass in the lib/fs suite"
fi

echo "PASS: provenance, deliverables, golden test both directions, agent repro both directions, project suites, hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0