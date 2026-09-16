#!/bin/bash
# Verifier for jackstay-larboard (librosa boolean-specshow colourbar bug).
# Proves the agent's fix in the real librosa tree at /app/src by
# (0) checking the sha256 trust anchors recorded at image build time,
# (1) asserting provenance (HEAD still the pinned parent commit; the fix
#     commit is unreachable from /app/src; every tracked file except the
#     single source file the bug lives in is byte-identical to the pinned
#     commit; no stray untracked files),
# (2) requiring the deliverables /app/repro.sh and /app/summary.md,
# (3) running the agent's own reproduction against the repaired tree (must
#     pass) and against a pristine pre-fix copy of the package baked at
#     /opt/prefix (must fail — proves the symptom is real and the
#     reproduction targets it),
# (4) asserting the norm-type discriminator itself, independently of the
#     agent's script, in both directions,
# (5) planting the upstream project's own regression test for this bug
#     (extracted from the fix commit at image build time into /opt/golden,
#     sha256-pinned) into a scratch tests/ tree together with its baseline
#     image, and running it against /app/src,
# (6) running a targeted slice of the project's own test_display suite
#     (specshow/colorbar/infer_cmap, all offline, pytest-mpl against the
#     tree's own baseline images) to prove the fix broke nothing else,
# (7) running four authored hidden cases that reach the same colour-normaliser
#     code path from inputs the upstream test does not use.
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

PARENT=c7aa2ce80a100cd901945589437c5acc55e38739
FIX=6ee6e4fc2d0d276158e0b21d61cfa49abc8ad771
GIT=/usr/bin/git

cd /app/src || fail "/app/src is missing"

# 0.5) network isolation. This task's integrity depends on the fix commit
#      being unreachable from the trial clone, which holds only while the
#      container has no network. If the trial container can actually fetch
#      from the internet, an agent could have pulled the fixed source instead
#      of finding it, so the verifier refuses to score (fail closed). Bounded
#      probe: a real TLS handshake to the upstream host and the package index
#      (raw TCP connect is not a signal — the egress proxy accepts the
#      connection and then cuts it, which is why git fetch / pip download /
#      curl all fail at the TLS layer when the policy is no-network).
if ( cd / && timeout 40 python3 - <<'EOF' >/tmp/netprobe.out 2>&1
import socket, ssl, sys
HOSTS = [("github.com", 443), ("raw.githubusercontent.com", 443), ("pypi.org", 443)]
def tls_ok(host, port, timeout=6):
    try:
        ctx = ssl.create_default_context()
        with socket.create_connection((host, port), timeout=timeout) as raw:
            with ctx.wrap_socket(raw, server_hostname=host) as tls:
                return True
    except Exception as e:
        return False
ok = any(tls_ok(h, p) for h, p in HOSTS)
print("REACHABLE" if ok else "OFFLINE")
sys.exit(0 if ok else 1)
EOF
)
then
    cat /tmp/netprobe.out >> "$LOG"
    fail "trial container can make TLS connections to the internet; the fix would be fetchable, refusing to score (see $LOG)"
fi

# 0) integrity anchors: the golden test bytes, the baseline image and the
#    pristine pre-fix package were sha256-pinned at image build time; if any
#    was substituted (an adversarial root trial could touch /opt), the
#    verifier must not trust it.
if ! ( cd / && sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 ); then
    fail "golden/pre-fix integrity check failed (substituted file)"
fi

# 1) provenance: still at the pinned parent commit, no commits added.
if [ "$("$GIT" rev-parse HEAD)" != "$PARENT" ]; then
    fail "HEAD is $("$GIT" rev-parse HEAD), expected pinned $PARENT"
fi
if "$GIT" cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "fix commit is reachable from /app/src"
fi
if [ "$("$GIT" rev-list --all --count)" != "1" ]; then
    fail "trial clone contains more than one commit"
fi

# 2) scope: exactly one tracked file (the source file the bug lives in) may
#    differ from the pinned commit, and no untracked non-ignored files. This
#    is a CONTENT check (hashes of the on-disk bytes against the pinned
#    blobs), so assume-unchanged/skip-worktree tricks cannot hide changes.
ok=1
while IFS= read -r -d '' f; do
    case "$f" in
        librosa/display.py) : ;;
        *)
            want=$("$GIT" rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            have=$("$GIT" hash-object -- "$f" 2>/dev/null || true)
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

# 3) deliverables: the agent's own reproduction and change summary.
[ -s /app/repro.sh ] || fail "/app/repro.sh is missing or empty"
[ -x /app/repro.sh ] || fail "/app/repro.sh is not executable"
[ -s /app/summary.md ] || fail "/app/summary.md is missing or empty"

# 4) the agent's reproduction, both directions. Against the repaired tree it
#    must exit 0; against the pristine pre-fix package it must exit nonzero.
if ! LIBROSA_TREE=/app/src /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
LIBROSA_TREE=/opt/prefix /app/repro.sh > /tmp/repro_prefix.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "agent repro passed against the PRE-FIX package (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix tree (see $LOG)"
fi

# 5) the discriminating oracle asserted independently of the agent's script:
#    the repaired tree must attach a BoundaryNorm([0, 0.5, 1]) to a boolean
#    specshow image; the pristine pre-fix concept must still attach a plain
#    Normalize.
if ! ( cd / && PYTHONPATH=/app/src python3 - <<'EOF' > /tmp/normchk_fixed.out 2>&1
import sys
import matplotlib
matplotlib.use("Agg")
import numpy as np, matplotlib.pyplot as plt
from matplotlib.colors import BoundaryNorm
import librosa, librosa.display
data = (np.random.default_rng(7).random((8, 8)) > 0.5)
fig, ax = plt.subplots()
img = librosa.display.specshow(data, ax=ax)
plt.close(fig)
norm = img.norm
fixed = (isinstance(norm, BoundaryNorm)
         and [float(b) for b in norm.boundaries] == [0.0, 0.5, 1.0])
print("norm_type=", type(norm).__name__, "boundaries=", list(norm.boundaries), "fixed=", fixed)
sys.exit(0 if fixed else 1)
EOF
)
then
    echo "verifier norm check (fixed tree) failed; got:" >> "$LOG"
    cat /tmp/normchk_fixed.out >> "$LOG"
    fail "boolean specshow did not get a BoundaryNorm([0,0.5,1]) on the repaired tree (see $LOG)"
fi
echo "norm check fixed: $(cat /tmp/normchk_fixed.out)" >> "$LOG"
# the pre-fix concept must still have the bug: plain Normalize
if ( cd / && PYTHONPATH=/opt/prefix python3 - <<'EOF' > /tmp/normchk_pre.out 2>&1
import sys
import matplotlib
matplotlib.use("Agg")
import numpy as np, matplotlib.pyplot as plt
from matplotlib.colors import BoundaryNorm
import librosa, librosa.display
fig, ax = plt.subplots()
img = librosa.display.specshow((np.random.default_rng(9).random((6, 6)) > 0.5), ax=ax)
plt.close(fig)
bogus = isinstance(img.norm, BoundaryNorm)
print("type=", type(img.norm).__name__, "bogus_boundary_on_prefix=", bogus)
sys.exit(0 if bogus else 1)
EOF
)
then
    cat /tmp/normchk_pre.out >> "$LOG"
    fail "pre-fix package /opt/prefix unexpectedly shows the FIXED behaviour (see $LOG)"
fi
echo "norm check pre: $(cat /tmp/normchk_pre.out)" >> "$LOG"

# 6) plant the upstream regression test (golden bytes, from the fix commit)
#    into a SCRATCH tests/ tree in /tmp, so /app/src/tests stays untouched,
#    and run it against the agent's tree.
rm -rf /tmp/gtest
mkdir -p /tmp/gtest/tests/baseline_golden
cp /opt/golden/test_display.py /tmp/gtest/tests/test_display.py || fail "cannot plant golden test_display.py"
cp /opt/golden/conftest.py /tmp/gtest/tests/conftest.py || fail "cannot plant golden conftest.py"
cp /opt/golden/test_specshow_boolean_norm.png /tmp/gtest/tests/baseline_golden/ || fail "cannot plant golden baseline png"
cp /app/src/tests/test_audio.ogg /app/src/tests/test_audio.flac /tmp/gtest/tests/ || fail "cannot copy audio fixtures"
( cd /tmp/gtest && PYTHONPATH=/app/src python3 -m pytest tests/test_display.py -k "boolean_norm" \
      -o addopts="" --mpl --mpl-baseline-path=tests/baseline_golden \
      -p no:cacheprovider -q > /tmp/golden.out 2>&1 )
rc=$?
if [ "$rc" -ne 0 ]; then
    tail -30 /tmp/golden.out >&2
    fail "upstream regression test test_specshow_boolean_norm did not pass (see /tmp/golden.out)"
fi
grep -q "1 passed" /tmp/golden.out || fail "golden test did not actually run and pass (see /tmp/golden.out)"

# 7) a targeted slice of the project's OWN existing test suite covering the
#    same drawing machinery must stay green on the repaired tree (pytest-mpl
#    pixel comparisons included, against the tree's own baseline images).
( cd /app/src && python3 -m pytest tests/test_display.py \
      -k "specshow or colorbar or infer_cmap" \
      -o addopts="" --mpl --mpl-baseline-path=tests/baseline_images/test_display \
      -p no:cacheprovider -q > /tmp/existing.out 2>&1 )
rc=$?
if [ "$rc" -ne 0 ]; then
    tail -30 /tmp/existing.out >&2
    fail "project's existing display tests failed on the repaired tree (see /tmp/existing.out)"
fi
NPASS=$(grep -Eo '^[0-9]+ passed' /tmp/existing.out | grep -Eo '^[0-9]+' || true)
if [ -z "$NPASS" ] || [ "$NPASS" -lt 12 ]; then
    echo "existing-suite run passed but only '$NPASS' tests:" >> "$LOG"
    tail -5 /tmp/existing.out >> "$LOG"
    fail "existing-suite slice ran too few tests (see /tmp/existing.out)"
fi

# 8) authored hidden cases: other boolean shapes and sparsity, a float-input
#    guard, and the explicit-cmap/user-norm override semantics. Each is a
#    deterministic python script that exits 0 iff the asserted behaviour
#    holds on the agent's tree.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    [ -f "$case/run.py" ] || fail "hidden case $name: missing run.py"
    if ! LIBROSA_TREE=/app/src python3 "$case/run.py" > /tmp/hc-$name.out 2>&1; then
        echo "hidden case $name failed on the repaired tree; stdout:" >> "$LOG"
        head -12 /tmp/hc-$name.out >> "$LOG"
        fail "hidden case $name: assertion failed (see $LOG)"
    fi
    marker=$(grep -Eo '^[A-Z][A-Z0-9 ]*OK' /tmp/hc-$name.out | head -1)
    if [ -z "$marker" ]; then
        echo "hidden case $name printed no PASS marker; stdout:" >> "$LOG"
        head -12 /tmp/hc-$name.out >> "$LOG"
        fail "hidden case $name: missing PASS marker (see $LOG)"
    fi
    echo "hidden case $name: $marker" >> "$LOG"
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 4 ] || fail "only $CASES hidden case(s) ran; expected 4"

echo "PASS: provenance, deliverables, repro both directions, independent norm oracle, upstream regression test, existing suite slice, and all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0