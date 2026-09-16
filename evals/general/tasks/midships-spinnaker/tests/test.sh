#!/bin/bash
# Verifier for midships-spinnaker (real upstream clone: psf/requests, pinned
# at the buggy parent commit 0b401c76b6e80a4eecf3c690085b2553f6e261ca).
#
# The agent had to (a) author its own failing reproduction at /app/reproduce.py
# from the user-visible symptom alone and (b) repair the real source tree so a
# wrapped streaming body is recognized and survives a 307 redirect re-post.
#
# This verifier:
#   1. proves provenance (HEAD still the pinned commit, single commit, object
#      store holds only that commit, fix commit unreachable);
#   2. executes the agent's reproduce.py against a pristine copy of the parent
#      source (regenerated at verify time from the pinned commit's object store
#      via `git archive`) and requires it to FAIL there;
#   3. executes the agent's reproduce.py against the repaired tree and requires
#      exit 0 + a REPRO-OK line;
#   4. blob-level scope check: every tracked file except the single
#      root-cause source file must be byte-identical to the pinned commit and
#      no untracked non-ignored files may exist (the repo's own .gitignore
#      covers egg-info/__pycache__/.pytest_cache produced by the editable
#      install and by pytest);
#   5. runs the project's OWN upstream regression test for this bug
#      (tests/test_requests.py::TestRequests::test_getattr_proxy_stream_follows_redirect
#      as it exists at the fix commit, extracted at image build time into
#      /opt/golden and sha256-verified so the agent cannot edit it);
#   6. runs three authored hidden cases (different payloads, methods, wrapper
#      shapes) exercising the same code path;
#   7. runs a subset of the project's own test suite to prove nothing else
#      broke.
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

PARENT=0b401c76b6e80a4eecf3c690085b2553f6e261ca
FIX=6404f345e562d962abe6700a1c357ec1e7e18232
GOLDEN_SHA256=c97eaf5958378b2117fdb88b5df031002772a9f24ba5484b91fe983c5f51cc80

cd /app/src || fail "/app/src is missing"

# 0) fix commit must not be reachable (the answer must not exist as an object).
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "the fix commit is reachable from the working clone"
fi

# 1) provenance
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if [ "$(git rev-list HEAD --count)" != "1" ]; then
    fail "clone contains history beyond the pinned parent commit"
fi
if [ "$(git fsck --no-reflogs --unreachable 2>/dev/null | wc -l)" != "0" ]; then
    fail "object store contains unreachable objects (see $LOG)"
fi

# 2) the deliverable exists and is non-empty
[ -f /app/reproduce.py ] || fail "/app/reproduce.py is missing"
[ -s /app/reproduce.py ] || fail "/app/reproduce.py is empty"

# 3) the agent's own reproduction must FAIL against the pristine parent source.
# The pristine source is regenerated HERE from the object store of /app/src
# (git archive of the pinned parent commit) rather than trusted from a
# build-time copy, so the check stays honest even if the agent tampered with
# or deleted /opt/presolve during the trial.
rm -rf /tmp/vrfy-presolve && mkdir -p /tmp/vrfy-presolve
if ! git -C /app/src archive "$PARENT" src | tar -x -C /tmp/vrfy-presolve 2>/dev/null; then
    fail "could not regenerate pristine parent source from the object store"
fi
if [ ! -f /tmp/vrfy-presolve/src/requests/models.py ]; then
    fail "regenerated pristine source is incomplete"
fi
if PYTHONPATH=/tmp/vrfy-presolve/src python3 /app/reproduce.py > /tmp/repro_presolve.out 2>&1; then
    fail "reproduce.py exited 0 against the pristine parent source: it does not reproduce the bug"
fi
if grep -q '^REPRO-OK' /tmp/repro_presolve.out; then
    fail "reproduce.py printed REPRO-OK against the pristine parent source"
fi

# 4) the agent's own reproduction must PASS against the repaired tree
python3 /app/reproduce.py > /tmp/repro_repaired.out 2>&1
if [ $? -ne 0 ]; then
    tail -20 /tmp/repro_repaired.out
    fail "reproduce.py failed against the repaired tree"
fi
if ! grep -q '^REPRO-OK' /tmp/repro_repaired.out; then
    fail "reproduce.py did not print REPRO-OK against the repaired tree"
fi

# 5) scope: only the root-cause source file may differ from the pinned commit,
#    compared at the BLOB level (assume-unchanged cannot hide a dirty file).
#    Symlinks are compared by their link target (git hash-object cannot hash a
#    link to a directory, e.g. the tests/certs/*/ca entries).
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        src/requests/models.py) : ;;
        *)
            mode=$(git ls-files -s -- "$f" | awk '{print $1}')
            if [ "$mode" = "120000" ]; then
                want=$(git show "$PARENT:$f" 2>/dev/null || true)
                have=$(readlink -- "$f" 2>/dev/null || true)
            else
                want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
                have=$(git hash-object -- "$f" 2>/dev/null || true)
            fi
            if [ -z "$want" ] || [ "$have" != "$want" ]; then
                echo "out-of-scope modified/deleted tracked file: $f" >> "$LOG"; ok=0
            fi
            ;;
    esac
done < <(git ls-files -z)
while IFS= read -r -d '' f; do
    echo "untracked non-ignored file: $f" >> "$LOG"; ok=0
done < <(git ls-files --others -z --exclude-standard)
if [ "$ok" != "1" ]; then
    fail "working tree modified outside the intended source file (see $LOG)"
fi

# 6) golden regression test: untouched upstream bytes, sha256-pinned, planted
#    into the project test suite and run through the project's own machinery.
have=$(sha256sum /opt/golden/test_requests.py | awk '{print $1}')
if [ "$have" != "$GOLDEN_SHA256" ]; then
    fail "golden test file does not match the extracted upstream regression test"
fi
cp /opt/golden/test_requests.py /app/src/tests/test_requests.py
python3 -m pytest -q '/app/src/tests/test_requests.py::TestRequests::test_getattr_proxy_stream_follows_redirect' \
    -p no:cacheprovider > /tmp/golden.log 2>&1
if [ $? -ne 0 ]; then
    tail -30 /tmp/golden.log
    fail "the project's own regression test for this bug failed on the repaired tree"
fi
grep -q '1 passed' /tmp/golden.log || fail "the regression test did not actually run"
cd /app/src && git checkout -- tests/test_requests.py

# 7) hidden cases: same code path, inputs the upstream test does not use
for c in case1 case2 case3; do
    if [ ! -d "/tests/hidden/$c" ]; then
        fail "hidden case directory /tests/hidden/$c is missing"
    fi
    python3 -m pytest -q "/tests/hidden/$c" -p no:cacheprovider > "/tmp/hidden_$c.log" 2>&1
    if [ $? -ne 0 ]; then
        tail -30 "/tmp/hidden_$c.log"
        fail "hidden case $c failed"
    fi
    grep -q 'passed' "/tmp/hidden_$c.log" || fail "hidden case $c did not run"
done

# 8) project's own suite subset (offline, self-contained) still passes
cd /app/src || fail "/app/src is missing"
python3 -m pytest -q \
    tests/test_utils.py tests/test_structures.py tests/test_packages.py tests/test_hooks.py \
    -p no:cacheprovider > /tmp/suite.log 2>&1
if [ $? -ne 0 ]; then
    tail -30 /tmp/suite.log
    fail "the project's own test suite subset failed on the repaired tree"
fi
grep -q 'passed' /tmp/suite.log || fail "the project's own suite subset did not run"

echo 1 > /logs/verifier/reward.txt
exit 0