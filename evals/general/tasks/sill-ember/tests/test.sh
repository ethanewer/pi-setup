#!/bin/bash
# Verifier for sill-ember: proves the agent's fix in the real
# expressjs/express tree at /app/src by (1) asserting provenance (HEAD still
# the pinned parent commit; every tracked file except the single replacement
# source file is byte-identical to it; no stray untracked files; node_modules
# content-identical to the built image), (2) requiring /app/summary.md and
# /app/repro.js, (3) running the agent's own reproduction script against a
# pristine pre-fix copy of the tree (must FAIL there) and against the
# repaired tree (must PASS), (4) running a targeted selection of the
# project's existing response tests, (5) planting the upstream project's own
# regression test for this bug (extracted from the fix commit at image build
# time into /opt/golden) and running it under the project's own runner (all
# 10 cases must pass), and (6) running three authored hidden supertest cases
# that reach the same code path from inputs the upstream test does not use.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
# Planting a reward file during the agent phase must never survive: the
# verifier always re-asserts 0 up front, before any check runs. Every
# failure path still writes 0 explicitly and success ends with echo 1.
echo 0 > /logs/verifier/reward.txt
LOG=/logs/verifier/verifier.log
: > "$LOG"

fail() {
    echo "FAIL: $1"
    echo "FAIL: $1" >> "$LOG"
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

PARENT=a1fa90fcea7d8e844e1c9938ad095d62669c3abd
FIX=a003cfab034fbadb1c78ae337ee8ab389adda217
GOLDEN_SHA=42b13505a3cce2ed8b4c3921beb6fb99d800034754d2ce8080ef9df7cf7aa35c
MOCHA=./node_modules/.bin/mocha

cd /app/src || fail "/app/src is missing"

# 1) the tree must still be at the pinned parent commit: no commits added,
#    and nothing can hide work from the blob-level scope check below.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) the fix commit must not be present in the object store (it never was:
#    the clone is shallow at the parent and origin was removed at build
#    time; a forged object would fail the SHA-1 integrity check).
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit object is present in /app/src/.git"
fi

# 3) scope: every change must live in exactly the one source file the bug
#    is in (the file that defines the location helper, discovered by the
#    agent, not named here). This is a CONTENT check, not a git-status
#    check: we hash the actual bytes of every tracked file on disk against
#    the pinned commit's own blob, so assume-unchanged/skip-worktree tricks
#    cannot hide a dirty file, and we refuse any untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        lib/response.js)
            # The fix must be an edit of this regular file. A worktree
            # file-type swap (lib/response.js replaced by a symlink to a
            # fixed copy hidden in an excluded/outside file) would dodge
            # the blob comparison above while the loaded code is fixed.
            if [ -L lib/response.js ]; then
                echo "lib/response.js is a symlink (worktree file-type swap)" >> "$LOG"; ok=0
            fi
            ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            have=$(git hash-object -- "$f" 2>/dev/null || true)
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

# 4) node_modules must be content-identical to the installed image (a
#    hostile tree must not be able to fake the mocha/supertest harness).
want_nm=$(cat /opt/node_modules.sha256 2>/dev/null || true)
if [ -z "$want_nm" ]; then
    fail "/opt/node_modules.sha256 is missing"
fi
# The pin covers regular files AND symlink targets: node_modules/.bin/*
# are symlinks (npm), and a hostile tree must not be able to re-point a
# test-runner symlink off-tree while the file-content hash still matches.
have_nm=$( ( find /app/src/node_modules -type f -print0 | sort -z | xargs -0 sha256sum; \
             find /app/src/node_modules -type l -printf '%p|%l\n' | sort ) \
           | sha256sum | cut -d' ' -f1 )
if [ "$have_nm" != "$want_nm" ]; then
    fail "node_modules contents differ from the built image (tampered harness)"
fi

# 5) deliverable: the agent's own change summary must exist, be non-empty,
#    and describe the bug it fixed.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"
grep -qi "URL" /app/summary.md || fail "/app/summary.md does not describe the bug"

# 6) the agent's own reproduction (deliverable): it must FAIL against a
#    pristine pre-fix copy of the tree (so it genuinely detects the bug)
#    and PASS against the repaired tree. The pre-fix copy is unforgeable:
#    `git archive HEAD` reads the committed parent tree from the object
#    store, not the (possibly fixed) working tree.
[ -s /app/repro.js ] || fail "/app/repro.js is missing or empty"
PFX=$(mktemp -d /tmp/sill-prefix.XXXXXX)
git archive HEAD | tar -x -C "$PFX" || fail "could not materialise the pre-fix tree"
ln -s /app/src/node_modules "$PFX/node_modules"
( cd /app/src && NODE_PATH=/app/src/node_modules node /app/repro.js "$PFX" > /tmp/repro-prefix.log 2>&1 )
prc=$?
if [ "$prc" -eq 0 ]; then
    tail -20 /tmp/repro-prefix.log >&2
    fail "repro exited 0 against a pristine PRE-FIX tree — it does not reproduce the bug"
fi
( cd /app/src && NODE_PATH=/app/src/node_modules node /app/repro.js /app/src > /tmp/repro-fixed.log 2>&1 )
frc=$?
if [ "$frc" -ne 0 ]; then
    tail -20 /tmp/repro-fixed.log >&2
    fail "repro still fails on your tree (exit $frc) — the bug is not fixed (see output)"
fi
[ -z "${PFX:-}" ] || rm -rf "$PFX"

# 7) a targeted selection of the project's OWN existing tests must remain
#    green after the fix.
EXISTING="test/res.location.js test/res.redirect.js test/res.set.js test/res.type.js test/res.send.js test/res.json.js"
if ! $MOCHA --require test/support/env $EXISTING > /tmp/existing.out 2>&1; then
    tail -30 /tmp/existing.out >&2
    fail "project's existing response tests failed (see /tmp/existing.out)"
fi
grep -q "passing" /tmp/existing.out || fail "existing selection produced no passing summary (see /tmp/existing.out)"

# 8) plant the upstream regression test (golden bytes, extracted from the
#    fix commit at image build time; never part of this task tree) and run
#    it under the project's own runner. All 10 cases must pass and the count
#    must actually be printed (a neutralised run leaves no summary). The
#    planted bytes are pinned to the fix commit's own blob: /opt/golden is
#    read-only to the agent, so the golden test cannot be scrubbed.
cp /opt/golden/res.location.js test/res.location.js || fail "cannot plant golden regression test"
have_gs=$(sha256sum test/res.location.js | cut -d' ' -f1)
if [ "$have_gs" != "$GOLDEN_SHA" ]; then
    fail "golden regression test is not the fix commit's blob (sha256 $have_gs)"
fi
if ! $MOCHA --require test/support/env test/res.location.js > /tmp/golden.out 2>&1; then
    tail -30 /tmp/golden.out >&2
    fail "upstream regression test for this bug did not pass (see /tmp/golden.out)"
fi
grep -q "10 passing" /tmp/golden.out || {
    tail -30 /tmp/golden.out >&2
    fail "golden regression test did not actually run 10 passing cases (see /tmp/golden.out)"
}

# 9) three authored hidden cases: other inputs reaching the same decision
#    path that the upstream regression test does not use (the redirect
#    helper with a URL object, a URL object carrying a query string and
#    fragment, and another non-string coercible value). Each drives the
#    project's own supertest and must exit 0.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    : > "/tmp/hc-$name.out"
    ( cd /app/src && NODE_PATH=/app/src/node_modules node "$case/run.js" ) > "/tmp/hc-$name.out" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "hidden case $name: node exited $rc; output:" >> "$LOG"
        head -20 "/tmp/hc-$name.out" >> "$LOG"
        fail "hidden case $name did not pass (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected 3"

echo "PASS: provenance, summary, two-direction repro, existing suite, upstream regression test, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0