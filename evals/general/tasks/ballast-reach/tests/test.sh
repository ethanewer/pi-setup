#!/bin/bash
# Verifier for ballast-reach: proves the agent's fix in the real
# pypa/setuptools tree at /app/src by (1) asserting provenance (HEAD still
# the pinned parent commit; every tracked file except the pattern-matching
# module and its optional normalization helper is byte-identical to it; no
# stray untracked files), (2) requiring /app/summary.md, (3) planting the
# project's OWN regression tests for the bug (extracted from the fix commit
# at image build time into /opt/golden; the agent's tree predates them) and
# running the whole planted test file, which must pass entirely, (4) running
# five authored hidden cases that reach the same matching code path from
# inputs the upstream tests do not use — including an end-to-end sdist build.
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

PARENT=84ed5913724df5a12dc804e1d5efe12508e706d2
export PYTHONPYCACHEPREFIX=/tmp/pycache

cd /app/src || fail "/app/src is missing"

# 0) runtime integrity. The verifier runs in the SAME container the agent
#    worked in, so a "fix" must live in the graded tree (/app/src), not in
#    the interpreter it runs on. Any change outside /app/src between image
#    build and now -- a sitecustomize shim, a replaced python3 binary, an
#    injected site-packages module, an edited /opt/golden test file -- moves
#    the canonical fingerprint of /usr/local plus the trusted tools away from
#    the build-time value. The expected fingerprint was committed to this
#    tests/ tree (re-uploaded fresh from the host at verify time; the agent
#    never sees it), so it cannot be forged from inside the container.
#    Regenerate it after any change to the Dockerfile with:
#      docker run --rm <image> cat /opt/runtime.manifest | sha256sum
EXPECT_FP=$(tr -d '[:space:]' < /tests/runtime-fingerprint.txt 2>/dev/null || true)
[ -n "$EXPECT_FP" ] || fail "missing /tests/runtime-fingerprint.txt (regenerate from /opt/runtime.manifest)"
( cd / \
  && { find usr/local/bin usr/local/lib/python3.12 -type f -print0 \
       | sort -z | xargs -0 sha256sum; \
       sha256sum bin/bash usr/bin/git opt/golden/test_manifest.py; } \
       | sort ) > /tmp/runtime.now
GOT_FP=$(sha256sum /tmp/runtime.now | awk '{print $1}')
if [ "$GOT_FP" != "$EXPECT_FP" ]; then
    echo "runtime integrity: expected $EXPECT_FP, got $GOT_FP" >&2
    echo "diff (build-time manifest vs live filesystem):" >&2
    diff /opt/runtime.manifest /tmp/runtime.now 2>/dev/null | head -20 >&2 || true
    fail "runtime integrity check failed: files outside /app/src changed (shims are not a fix)"
fi

# 1) the tree must still be at the pinned parent commit: no commits added,
#    and nothing can hide work from the blob-level scope check below.
if [ "$(git rev-parse HEAD 2>/dev/null)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD 2>/dev/null), expected pinned $PARENT"
fi

# 2) scope: every change must live in the module that implements MANIFEST.in
#    pattern matching (the one defining translate_pattern, discovered by the
#    agent, not named here) and optionally one new helper module beside it.
#    This is a CONTENT check, not a git-status check: we hash the actual
#    bytes of every tracked file on disk against the pinned commit's own
#    blob, so assume-unchanged/skip-worktree tricks cannot hide a dirty
#    file. Staged content is also rejected (git add must not have been used).
if ! git diff --quiet --cached; then
    fail "staged changes present (run git status); the graded tree must be a working-tree change only"
fi
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        setuptools/command/egg_info.py|setuptools/unicode_utils.py) : ;;
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
# Untracked files: allowed are the optional new helper module and generated
# build/test artifacts (the repository ships no .gitignore, and the image's
# own `pip install -e .` created setuptools.egg-info/ at build time).
while IFS= read -r -d '' f; do
    case "$f" in
        setuptools/unicode_utils.py|*/__pycache__/*|__pycache__/*|*/__pycache__|*.pyc|.pytest_cache/*|*/.pytest_cache/*|*.egg-info/*|*.egg-info|build/*) : ;;
        *) echo "untracked non-allowed file: $f" >> "$LOG"; ok=0 ;;
    esac
done < <(git ls-files --others -z)
if [ "$ok" != "1" ]; then
    tail -30 "$LOG"
    fail "working tree modified outside the matching module (see $LOG)"
fi

# 3) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) plant the project's OWN regression tests for this bug (golden bytes,
#    extracted from the fix commit at image build time; never part of this
#    task tree) into the tree's test file and run the WHOLE file. On the
#    unfixed tree the two regression tests fail and the run exits non-zero.
cp /opt/golden/test_manifest.py setuptools/tests/test_manifest.py \
    || fail "cannot plant golden test file"
if ! python3 -m pytest -q -p no:cacheprovider setuptools/tests/test_manifest.py > /tmp/golden.out 2>&1; then
    tail -40 /tmp/golden.out >&2
    fail "planted test_manifest.py did not pass in full (see /tmp/golden.out)"
fi
grep -E "[0-9]+ passed" /tmp/golden.out | tail -1
grep -qE "^69 passed" /tmp/golden.out || {
    tail -10 /tmp/golden.out >&2
    fail "unexpected pass count in /tmp/golden.out (expected the full file green)"
}

# 5) the two upstream regression tests must actually have run and passed
#    (a neutralised run would leave no such lines even with exit 0).
if ! python3 -m pytest -p no:cacheprovider -v -k 'unicode_normalization' setuptools/tests/test_manifest.py > /tmp/golden2.out 2>&1; then
    tail -30 /tmp/golden2.out >&2
    fail "regression test selection failed (see /tmp/golden2.out)"
fi
grep -q "test_translate_pattern_unicode_normalization PASSED" /tmp/golden2.out || {
    fail "test_translate_pattern_unicode_normalization did not run and pass (see /tmp/golden2.out)"
}
grep -q "test_global_exclude_unicode_normalization PASSED" /tmp/golden2.out || {
    fail "test_global_exclude_unicode_normalization did not run and pass (see /tmp/golden2.out)"
}

# 6) authored hidden cases: other inputs reaching the same matching code
#    path. Every one fails on the unfixed tree and must pass now.
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
        echo "hidden case $name: script exited $rc (expected 0); stderr:" >> "$LOG"
        head -12 "$work/stderr.txt" >> "$LOG"
        fail "hidden case $name: script exited $rc (see $LOG)"
    fi
    if ! cmp -s "$work/stdout.txt" "$work/expected"; then
        echo "hidden case $name: stdout mismatch; got:" >> "$LOG"
        head -8 "$work/stdout.txt" >> "$LOG"
        fail "hidden case $name: output mismatch (see $LOG)"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 5 ] || fail "only $CASES hidden case(s) ran; expected 5"

echo "PASS: provenance, /app/summary.md, planted upstream regression tests + full test file, all $CASES hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0