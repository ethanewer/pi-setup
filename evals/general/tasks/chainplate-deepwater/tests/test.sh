#!/bin/bash
# Verifier for chainplate-deepwater: proves the agent's fix in the real
# pytorch/vision tree at /app/src by (1) asserting provenance (HEAD still the
# pinned parent commit; every tracked file except the single fixed source file
# is byte-identical to it; no stray untracked files), (2) requiring
# /app/summary.md, (3) checking the installed-package mirror in /app/env runs
# the fixed tree bytes, (4) running the direct reproducer, and (5) planting
# the upstream project's own regression test for this bug (extracted from the
# fix commit at image-build time into /opt/golden) plus four authored
# hidden-case modules into the tree and running them together with the
# project's own TestConvertBoundingBoxFormat suite through the project's own
# pytest, offline.
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

PARENT=6940e19087cecb5108370703e207f7a33d9b478d
ALLOWED=torchvision/transforms/v2/functional/_meta.py
SP=/app/env/lib/python3.12/site-packages/torchvision
PY=/app/env/bin/python

cd /app/src || fail "/app/src is missing"

# Hardened input integrity: the golden test and the reproducer live in the
# image at /opt and are world-writable by the trial, so the verifier pins them
# to the bytes that were extracted at build time. A tampered golden test (e.g.
# a regression method reduced to `pass`) or a reproducer that prints OK
# unconditionally must fail here, not be trusted.
GOLDEN_HASH=9dd758d9595d7d9912c463a87f5c7935c7191de0  # fix commit 74d1285:test/test_transforms_v2.py
REPRO_HASH=74852604b35973747bf7ceab612ecc21a528f578   # environment/files/repro.py
[ -f /opt/golden/test_transforms_v2.py ] || fail "/opt/golden/test_transforms_v2.py missing"
if [ "$(git hash-object /opt/golden/test_transforms_v2.py 2>/dev/null)" != "$GOLDEN_HASH" ]; then
    fail "golden regression test at /opt/golden/test_transforms_v2.py is not the fix-commit bytes (tampered?)"
fi
[ -f /opt/repro.py ] || fail "/opt/repro.py missing"
if [ "$(git hash-object /opt/repro.py 2>/dev/null)" != "$REPRO_HASH" ]; then
    fail "reproducer at /opt/repro.py is not the shipped bytes (tampered?)"
fi

# The tree must actually be repaired: the bug lives in _meta.py, so the fix
# must change it. A container whose tree is byte-identical to the parent commit
# has not been fixed, no matter what the installed package does.
PARENT_META_BLOB=6b8f19f12f41b47b7c73047c10b8359f76290fa2
if [ "$(git hash-object /app/src/torchvision/transforms/v2/functional/_meta.py 2>/dev/null)" = "$PARENT_META_BLOB" ]; then
    fail "the bug's source file was not changed: /app/src is byte-identical to the pinned commit"
fi

# Wrapper defense: the installed package must be a faithful mirror of the tree
# for every mirrored module, not just _meta.py, so a "fix" hidden in another
# venv file (functional/__init__.py, _type_conversion.py, tv_tensors, ...) is
# caught. __pycache__ is the only permitted difference.
if ! diff -r -x '__pycache__' torchvision/transforms/v2 "$SP/transforms/v2" >/dev/null 2>&1; then
    fail "installed package transforms/v2 does not byte-match the tree (wrapper or stale mirror?)"
fi
if ! diff -r -x '__pycache__' torchvision/tv_tensors "$SP/tv_tensors" >/dev/null 2>&1; then
    fail "installed package tv_tensors does not byte-match the tree (wrapper or stale mirror?)"
fi

# Interpreter-startup hooks and .pth shims are a classic place to smuggle a
# wrapper that the tree provenance cannot see: reject any sitecustomize.py /
# usercustomize.py in site-packages and any .pth beyond the venv's own
# distutils-precedence.pth.
SITE=$(dirname "$SP")
if [ -e "$SITE/sitecustomize.py" ] || [ -e "$SITE/usercustomize.py" ]; then
    fail "unexpected interpreter-startup hook in site-packages (sitecustomize/usercustomize)"
fi
pth_count=$(ls "$SITE"/*.pth 2>/dev/null | wc -l)
if [ "$pth_count" != "1" ] || [ ! -f "$SITE/distutils-precedence.pth" ]; then
    fail "unexpected .pth shims in site-packages"
fi

# The tree must not smuggle pytest hooks or other files via the ignore
# mechanism: the pristine .git/info/exclude contains only comments, and the
# only conftest.py in the tree is the upstream-tracked test/conftest.py.
if awk 'NF && $1 !~ /^#/' /app/src/.git/info/exclude 2>/dev/null | grep -q .; then
    fail "active (non-comment) line in .git/info/exclude: ignored file smuggled into the tree"
fi
if find /app/src -name 'conftest.py' ! -path '/app/src/test/conftest.py' 2>/dev/null | grep -q .; then
    fail "conftest.py planted outside the tracked test/conftest.py"
fi

# 1) the tree must still be at the pinned parent commit: no commits added.
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi

# 2) scope: every change must live in exactly the one source file the bug is
#    in (discovered by the agent, not named here). CONTENT check, not a
#    git-status check: we hash the actual bytes of every tracked file on disk
#    against the pinned commit's own blob, so assume-unchanged tricks cannot
#    hide a dirty file, and we refuse any untracked non-ignored file.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        "$ALLOWED") : ;;
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            have=$(git hash-object -- "$f" 2>/dev/null || true)
            # symlinks hash their link target, not the target's bytes
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

# 3) deliverable: the agent's own change summary must exist.
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) the installed-package mirror must run the fixed tree bytes: a fix that
#    only touched /app/src but never refreshed /app/env is not a working fix,
#    and a fix that only touched the venv is not a tree fix (the scope check
#    above would have flagged the untouched tree only if it diffed; the mirror
#    check catches the first case).
if ! cmp -s /app/src/torchvision/transforms/v2/functional/_meta.py \
        "$SP/transforms/v2/functional/_meta.py"; then
    fail "installed-package mirror does not match the fixed tree: refresh /app/env (see /app/README-TESTING.md)"
fi

# 5) purge bytecode caches so no stale .pyc can shadow the fixed source.
find "$SP" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true

# 6) the direct reproducer must print OK on the fixed tree.
REPRO_OUT=$($PY /opt/repro.py 2>&1) || {
    echo "reproducer output:" >> "$LOG"
    echo "$REPRO_OUT" | tail -5 >> "$LOG"
    fail "direct reproducer failed (see $LOG)"
}
echo "$REPRO_OUT" | grep -q '^OK$' || {
    echo "reproducer output: $REPRO_OUT" >> "$LOG"
    fail "reproducer did not print OK (see $LOG)"
}

# 7) plant the golden upstream regression test and the authored hidden-case
#    modules into the project's own test tree, then run everything together
#    with the project's own pytest: the golden method, the whole
#    TestConvertBoundingBoxFormat class (reference-checked against
#    torchvision.ops.box_convert), and the hidden generalization cases.
GOLDEN=/opt/golden/test_transforms_v2.py
[ -f "$GOLDEN" ] || fail "/opt/golden/test_transforms_v2.py missing"
cp "$GOLDEN" test/test_transforms_v2.py || fail "cannot plant golden regression test"
HIDDEN=0
for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    for tf in "$case"test_chainplate_*.py; do
        [ -f "$tf" ] || continue
        name=$(basename "$tf")
        cp "$tf" "test/$name" || fail "cannot plant hidden case $tf"
        HIDDEN=$((HIDDEN + 1))
    done
done
if [ "$HIDDEN" -lt 2 ]; then
    fail "expected at least two authored hidden cases, found $HIDDEN"
fi

# Run from a neutral CWD with absolute test paths: running from /app/src would
# put the un-built source tree on sys.path and `import torchvision` would
# resolve to the wrong code. The repository's own pytest.ini addopts
# (warnings-as-errors) are disabled for this wheel-pinned venv; the runner is
# still the project's own pytest on the project's own test files.
cd /tmp || fail "no /tmp"

$PY -m pytest /app/src/test/test_transforms_v2.py \
    -k test_cxcywh_to_xyxy_odd_dimensions -p no:cacheprovider -o addopts='' \
    --tb=line > /tmp/verifier_golden.log 2>&1
rc=$?
cat /tmp/verifier_golden.log >> "$LOG"
if [ $rc -ne 0 ]; then
    tail -30 "$LOG"
    fail "upstream regression test test_cxcywh_to_xyxy_odd_dimensions failed (see $LOG)"
fi
grep -qE "1 passed" /tmp/verifier_golden.log || {
    fail "upstream regression test summary missing (see $LOG)"
}

$PY -m pytest /app/src/test/test_transforms_v2.py /app/src/test/test_chainplate_*.py \
    -k "TestConvertBoundingBoxFormat or chainplate" -p no:cacheprovider -o addopts='' \
    --tb=short -q > /tmp/verifier_suite.log 2>&1
rc=$?
cat /tmp/verifier_suite.log >> "$LOG"
if [ $rc -ne 0 ]; then
    tail -40 "$LOG"
    fail "project suite + hidden cases did not all pass (see $LOG)"
fi
grep -qE " passed" /tmp/verifier_suite.log || {
    fail "pytest summary for the class + hidden runs missing (see $LOG)"
}

echo "PASS: provenance, /app/summary.md, mirror refresh, reproducer, upstream regression test, TestConvertBoundingBoxFormat class, $HIDDEN hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0