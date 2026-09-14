#!/bin/bash
# Verifier for wale-beacon: proves the agent's fix in the real pytorch/vision
# tree at /app/src by (1) asserting the verifier's own trust anchors still
# match the sha256 pins recorded at image build time (golden test, pristine
# pre-fix module, venv python binary, and the full manifest of wheel files of
# the installed torchvision package, which would catch a planted stub that
# fakes the codec), (2) asserting provenance (HEAD still the pinned parent
# commit; the upstream fix commit is not reachable from this clone), (3)
# requiring every tracked file to be byte-identical to the parent commit
# except the single source file where the bug lives, and no stray untracked
# files, (4) requiring /app/repro.py (executable) and /app/summary.md
# (non-empty), (5) running the agent's reproduction against the pristine
# pre-fix module swapped into the installed package (must fail) as well as
# against the repaired tree (must pass), (6) running the project's own
# regression test (extracted from the upstream fix commit at image build time
# into /opt/golden, sha256-pinned) - it must fail on the pre-fix bytes and
# pass on the repaired tree, (7) running the project's existing TestJPEG test
# suite (5 parametrised nodes, all contiguous inputs) to prove the fix broke
# nothing else, and (8) running three authored hidden cases that reach the
# same JPEG code path from inputs the upstream test does not use - each must
# fail on the pre-fix bytes and pass on the repaired tree.
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

PARENT=c7ef957c29cadb0b5d053164bf5e763dfe49e829
FIX=50237caaf648140f0029b16f748c578a364ff15a
REL=torchvision/transforms/v2/functional/_augment.py
SITE=/app/env/lib/python3.12/site-packages/torchvision/transforms/v2/functional/_augment.py
FUNCDIR=/app/env/lib/python3.12/site-packages/torchvision/transforms/v2/functional

export PYTHONDONTWRITEBYTECODE=1
unset PYTHONPATH || true

# 0) integrity anchors. The verifier executes the tree, the golden test, the
#    pre-fix module, the venv python and the wheel codec; an adversarial agent
#    could otherwise swap any of them for a stub that fakes a green run. The
#    pins recorded at image build time detect substitution before anything is
#    executed. The torchvision manifest is checked from the site-packages
#    directory because its paths are recorded relative to it.
if ! sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/prefix.sha256 >/dev/null 2>&1 || \
   ! sha256sum -c /opt/pins/python.sha256 >/dev/null 2>&1; then
    fail "golden, pre-fix module or venv python integrity check failed (substituted file)"
fi
if ! ( cd /app/env/lib/python3.12/site-packages \
       && sha256sum -c /opt/pins/torchvision-site.sha256 >/dev/null 2>&1 ); then
    fail "installed torchvision package differs from the build-time manifest"
fi

# 1) provenance: the tree must still be at the pinned parent commit and the
#    upstream fix commit must not be reachable from this object store (an
#    agent that fetched or grafted the fix earns 0; the fix direction must
#    come from the agent's own work).
cd /app/src || fail "/app/src is missing"
if [ "$(git rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $(git rev-parse HEAD), expected pinned $PARENT"
fi
if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "upstream fix commit is reachable from /app/src (fetch/graft detected)"
fi

# 2) scope: every change must live in exactly the one source file the bug
#    lives in. This is a CONTENT check: the actual bytes of every tracked file
#    on disk are hashed against the pinned commit's own blob, so
#    assume-unchanged / skip-worktree tricks cannot hide a dirty file, and any
#    untracked non-ignored file is refused.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        "$REL") : ;;  # the one source file the bug lives in
        *)
            want=$(git rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            idx=$(git ls-files -s -- "$f" | awk '{print $2}')
            mode=$(git ls-files -s -- "$f" | awk '{print $1}')
            if [ "$idx" != "$want" ]; then
                echo "index oid mismatch for tracked file: $f" >> "$LOG"; ok=0; continue
            fi
            is_gitlink=0
            case "$mode" in
                160000*) is_gitlink=1 ;;
            esac
            if [ "$is_gitlink" -eq 0 ]; then
                case "$mode" in
                    120000*)
                        have=$(printf '%s' "$(readlink "$f")" | git hash-object --stdin 2>/dev/null || true)
                        ;;
                    *)
                        have=$(git hash-object -- "$f" 2>/dev/null || true)
                        ;;
                esac
                if [ -z "$have" ] || [ "$have" != "$want" ]; then
                    echo "worktree differs from parent for tracked file: $f" >> "$LOG"; ok=0
                fi
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

# 3) deliverables: the agent's own failing reproduction and change summary.
[ -s /app/repro.py ] || fail "/app/repro.py is missing or empty"
[ -x /app/repro.py ] || fail "/app/repro.py is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) the installed package must actually resolve the transform logic to the
#    fixed tree (the wheel's copy of the buggy module is a symlink to the
#    /app/src file). A tree fix that is never wired into the runtime passes
#    nothing.
if [ ! -L "$SITE" ]; then
    fail "site-packages _augment.py is not the symlink to /app/src (tree fix not wired into runtime)"
fi
if [ "$(readlink "$SITE")" != "/app/src/$REL" ]; then
    fail "site-packages _augment.py symlink target is $(readlink "$SITE"), expected /app/src/$REL"
fi

# every python run below must happen from OUTSIDE /app/src, or "import
# torchvision" resolves to the incomplete source-tree package instead of the
# installed wheel (the source package lacks the compiled extensions).
cd /tmp || fail "cannot cd /tmp"

# helper: put the pristine pre-fix module in place (returns the runtime to the
# unfixed state), run a command that must FAIL, then restore the symlink.
run_prefixed() { # $1 = description, rest = command...
    local desc=$1; shift
    rm -f "$SITE"
    cp /opt/prefix/_augment.py "$SITE"
    rm -rf "$FUNCDIR/__pycache__"
    "$@" > /tmp/prefix.out 2>&1
    local rc=$?
    rm -f "$SITE"
    ln -s "/app/src/$REL" "$SITE"
    rm -rf "$FUNCDIR/__pycache__"
    if [ "$rc" -eq 0 ]; then
        echo "$desc PASSED against the pre-fix module (expected failure); output:" >> "$LOG"
        head -10 /tmp/prefix.out >> "$LOG"
        return 1
    fi
    echo "ok: $desc fails against the pre-fix module (rc=$rc)"
    return 0
}

run_fixed() { # $1 = description, rest = command...
    local desc=$1; shift
    "$@" > /tmp/fixed.out 2>&1
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "$desc did not pass on the repaired tree (rc=$rc); output:" >> "$LOG"
        head -20 /tmp/fixed.out >> "$LOG"
        return 1
    fi
    echo "ok: $desc passes on the repaired tree"
    return 0
}

# 5) the agent's reproduction, both directions.
if ! run_prefixed "agent reproduction" /app/repro.py; then
    fail "agent reproduction did not fail on the pristine pre-fix module (fake/hardcoded repro?)"
fi
if ! run_fixed "agent reproduction" /app/repro.py; then
    fail "agent reproduction failed on the repaired tree"
fi

# 6) the project's own regression test for this bug (golden bytes, extracted
#    from the fix commit at image build time and sha256-pinned; never part of
#    this task tree). It must fail on the pre-fix bytes and pass on the
#    repaired tree.
if ! run_prefixed "upstream regression test" /app/env/bin/python -m pytest \
        /opt/golden/test_kernel_non_contiguous_leading_dimensions.py -p no:cacheprovider -q; then
    fail "upstream regression test passed against the pre-fix module - it does not exercise the bug"
fi
if ! run_fixed "upstream regression test" /app/env/bin/python -m pytest \
        /opt/golden/test_kernel_non_contiguous_leading_dimensions.py -p no:cacheprovider -q; then
    fail "upstream regression test failed on the repaired tree"
fi
grep -q "1 passed" /tmp/fixed.out || {
    tail -20 /tmp/fixed.out >&2
    fail "upstream regression test did not report 1 passed (see $LOG)"
}

# 6b) the re-encoding must be REAL, not an identity stub: the output of the
#    JPEG kernel must differ from its (noisy) input and must depend on the
#    quality parameter. Both properties are asserted in both directions, so a
#    cheat that passes by making the transform return its input (the golden
#    test only compares the two runs) is caught here.
PROBE=$(cat <<'PY'
import torch
from torchvision.transforms.v2 import functional as F
noise = torch.randint(0, 256, (2, 3, 3, 16, 16), dtype=torch.uint8).transpose(0, 1)
assert not noise.is_contiguous()
out = F.jpeg_image(noise, quality=75)
assert torch.equal(out, F.jpeg_image(noise.contiguous(), quality=75))
assert out.shape == noise.shape and out.dtype == noise.dtype
assert not torch.equal(out, noise), "output equals its input: JPEG re-encoding is stubbed"
low = F.jpeg_image(noise, quality=5)
high = F.jpeg_image(noise, quality=95)
assert not torch.equal(low, high), "quality has no effect: JPEG re-encoding is stubbed"
print("re-encode integrity probe OK")
PY
)
if ! run_prefixed "re-encode integrity probe" /app/env/bin/python -c "$PROBE"; then
    fail "re-encode integrity probe passed against the pre-fix module (stubbed re-encoding?)"
fi
if ! run_fixed "re-encode integrity probe" /app/env/bin/python -c "$PROBE"; then
    fail "re-encode integrity probe failed on the repaired tree (identity stub?)"
fi

# 7) the project's own existing JPEG tests (contiguous inputs, same code
#    path) must stay green on the repaired tree. The scope check above
#    guarantees the test file is byte-identical to the pinned commit.
cd /tmp || fail "cannot cd /tmp"
if ! /app/env/bin/python -m pytest \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[RGB-5]" \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[RGB-75]" \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[GRAY-5]" \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_image[GRAY-75]" \
      "/app/src/test/test_transforms_v2.py::TestJPEG::test_kernel_video" \
      -p no:cacheprovider -q > "$LOG.existing" 2>&1; then
    tail -30 "$LOG.existing" >&2
    fail "existing TestJPEG suite did not pass on the repaired tree (see $LOG.existing)"
fi
grep -q "5 passed" "$LOG.existing" || {
    tail -20 "$LOG.existing" >&2
    fail "existing TestJPEG suite did not report 5 passed (see $LOG.existing)"
}

# 8) three authored hidden cases reaching the same code path from inputs the
#    upstream test does not use (transposed video batch via jpeg_video; a
#    strided-slice image batch; a three-leading-dimension transpose). Each
#    must fail on the pre-fix bytes and pass on the repaired tree.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    rsh="$case/run.sh"
    [ -f "$rsh" ] || fail "hidden case $name: missing run.sh"
    if ! run_prefixed "hidden case $name" bash "$rsh"; then
        fail "hidden case $name did not fail on the pre-fix module - it does not exercise the bug"
    fi
    if ! run_fixed "hidden case $name" bash "$rsh"; then
        fail "hidden case $name failed on the repaired tree"
    fi
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 3 ] || fail "only $CASES hidden case(s) ran; expected at least 3"

echo "PASS: trust anchors, provenance, scope, deliverables, repro both directions, upstream regression test both directions, existing TestJPEG suite, and all hidden cases both directions"
echo 1 > /logs/verifier/reward.txt
exit 0