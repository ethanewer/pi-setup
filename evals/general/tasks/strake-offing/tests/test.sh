#!/bin/bash
# Verifier for strake-offing (matplotlib Axes.hist timedelta-input crash).
#
# Proves the agent's fix in the real matplotlib tree at /app/src by
#  (0) checking the sha256 trust anchors recorded at image build time
#      (golden test bytes + pristine pre-fix package; site-packages
#      snapshot, which closes sitecustomize/.pth monkeypatch attacks),
#  (1) asserting provenance (HEAD still the pinned parent commit; exactly one
#      commit; every tracked file except the single source file the bug lives
#      in is byte-identical to the pinned commit; no stray untracked files),
#  (2) requiring the deliverables /app/repro.sh and /app/summary.md,
#  (3) running the agent's own reproduction against the repaired tree (must
#      pass) and against a pristine pre-fix copy of the package baked at
#      /opt/prefix (must fail — proves the symptom is real and the
#      reproduction targets it),
#  (4) asserting the clean-TypeError discriminator independently of the
#      agent's script, in both directions, including that the /opt/prefix
#      import really resolved to the pre-fix copy,
#  (5) planting the upstream project's own regression test for this bug
#      (extracted from the fix commit at image build time into /opt/golden,
#      sha256-pinned, body byte-identical to the one in the upstream fixed
#      test_axes.py) and running it against the repaired tree (must pass) and
#      against the pre-fix concept (must fail),
#  (6) running a 25-test green slice of the project's own test_axes.py hist
#      suite to prove the fix broke nothing else,
#  (7) running five authored hidden cases that reach the same histogram code
#      path from inputs the upstream test does not use, including one that
#      requires non-duration histogram TypeErrors to keep their own messages.
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

PARENT=496ae85214a7029d5c8eca320cb45f013b535dfe
FIX=c72236701f0371d37c8a3232133347d5b350bc59
PIX=/app/src/build/cp312
GIT=/usr/bin/git
CLEAN="does not currently support timedelta inputs"
export PYTHONNOUSERSITE=1

cd /app/src || fail "/app/src is missing"

# 0) integrity anchors: the golden test bytes, the pristine pre-fix package
#    and the site-packages snapshot were pinned at image build time; if any
#    was substituted (an adversarial root trial could touch /opt or
#    site-packages), the verifier must not trust it.
if ! ( cd / && sha256sum -c /opt/pins/golden.sha256 >/dev/null 2>&1 ); then
    fail "golden/pre-fix integrity check failed (substituted file)"
fi
if ! ( cd /usr/local/lib/python3.12/site-packages && \
       find . -path '*/__pycache__/*' -prune -o -type f -print0 | sort -z | \
       xargs -0 sha256sum | diff -q /opt/pins/site-packages.sha256 - >/dev/null 2>&1 ); then
    fail "site-packages differs from the pinned snapshot (modified or injected file)"
fi

# 1) provenance: still at the pinned parent commit, exactly one commit.
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
        lib/matplotlib/axes/_axes.py) : ;;
        *)
            want=$("$GIT" rev-parse "$PARENT:$f" 2>/dev/null || true)
            if [ -z "$want" ]; then
                echo "tracked file not in parent tree: $f" >> "$LOG"; ok=0; continue
            fi
            if [ -L "$f" ]; then
                # git stores symlinks as a blob of the link text (no trailing
                # newline); hash the target string itself, not the file it
                # points at (readlink(1) pads a newline — strip it).
                have=$(printf '%s' "$(readlink "$f")" | "$GIT" hash-object --stdin)
            else
                have=$("$GIT" hash-object -- "$f" 2>/dev/null || true)
            fi
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
if ! MPL_TREE=/app/src /app/repro.sh > /tmp/repro_fixed.out 2>&1; then
    echo "agent repro failed on the repaired tree; stdout:" >> "$LOG"
    head -10 /tmp/repro_fixed.out >> "$LOG"
    fail "agent repro exited nonzero on the repaired tree (see $LOG)"
fi
MPL_TREE=/opt/prefix MESONPY_EDITABLE_SKIP=$PIX PYTHONPATH=/opt/prefix/lib \
    /app/repro.sh > /tmp/repro_prefix.out 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "agent repro passed against the PRE-FIX package (expected failure); stdout:" >> "$LOG"
    head -10 /tmp/repro_prefix.out >> "$LOG"
    fail "agent repro did not fail on the pre-fix concept (see $LOG)"
fi

# 5) the discriminating oracle asserted independently of the agent's script.
#    (a) repaired tree: both duration shapes must raise a TypeError whose
#        message contains the clean phrase; numeric binning stays correct.
if ! ( cd / && python3 - <<'EOF' > /tmp/probe_fixed.out 2>&1
import sys
import matplotlib
matplotlib.use("Agg")
import datetime
import matplotlib.pyplot as plt
import numpy as np

CLEAN = "does not currently support timedelta inputs"
fig, ax = plt.subplots()
for data in (np.array([1, 2, 5, 7], dtype="timedelta64[D]"),
             [datetime.timedelta(seconds=i) for i in range(5)]):
    try:
        ax.hist(data)
        print("hist accepted duration input without raising")
        sys.exit(1)
    except TypeError as exc:
        if CLEAN not in str(exc):
            print("opaque TypeError:", str(exc)[:120])
            sys.exit(1)
    except Exception as exc:
        print("opaque", type(exc).__name__, str(exc)[:120])
        sys.exit(1)
n, bins, patches = ax.hist(np.array([1.0, 2.0, 2.0, 7.0]), bins=3)
import numpy as np
want = np.histogram(np.array([1.0, 2.0, 2.0, 7.0]), bins=3)[0]
if not (list(n) == list(want) and int(n.sum()) == 4):
    print("numeric counts wrong:", list(n), "want", list(want))
    sys.exit(1)
print("fixed-tree probe OK: clean TypeError for both duration shapes")
sys.exit(0)
EOF
)
then
    echo "independent probe (repaired tree) failed; output:" >> "$LOG"
    cat /tmp/probe_fixed.out >> "$LOG"
    fail "repaired tree did not raise the clean TypeError (see $LOG)"
fi
echo "probe fixed: $(cat /tmp/probe_fixed.out)" >> "$LOG"

#    (b) pre-fix concept: the pristine copy must STILL crash opaquely — and
#        the probe must prove it really loaded /opt/prefix, not /app/src.
if ! ( cd / && MESONPY_EDITABLE_SKIP=$PIX PYTHONPATH=/opt/prefix/lib python3 - <<'EOF' > /tmp/probe_prefix.out 2>&1
import sys
import matplotlib
matplotlib.use("Agg")
import datetime
import matplotlib.pyplot as plt
import numpy as np

CLEAN = "does not currently support timedelta inputs"
assert matplotlib.__file__.startswith("/opt/prefix"), matplotlib.__file__
for data in (np.array([1, 2, 5, 7], dtype="timedelta64[D]"),
             [datetime.timedelta(seconds=i) for i in range(5)]):
    fig, ax = plt.subplots()
    try:
        ax.hist(data)
        print("pre-fix concept ACCEPTED duration input (bug missing)")
        sys.exit(1)
    except Exception as exc:
        if CLEAN in str(exc):
            print("pre-fix concept shows the FIXED message:", str(exc)[:120])
            sys.exit(1)
    finally:
        plt.close(fig)
fig, ax = plt.subplots()
n, bins, patches = ax.hist(np.array([1.0, 7.0, 3.0, 9.0]), bins=2)
if list(n) != [2.0, 2.0]:
    print("pre-fix concept numeric hist broken:", list(n))
    sys.exit(1)
print("pre-fix probe OK: opaque crash retained, numeric hist intact, tree = " + matplotlib.__file__)
sys.exit(0)
EOF
)
then
    cat /tmp/probe_prefix.out >> "$LOG"
    fail "pre-fix concept /opt/prefix does not retain the bug (see $LOG)"
fi
echo "probe prefix: $(cat /tmp/probe_prefix.out)" >> "$LOG"

# 6) plant the upstream regression test (golden bytes, from the fix commit)
#    and run it against the repaired tree (must pass) and against the
#    pristine pre-fix concept (must fail). First prove the planted file's
#    function body is byte-identical to the one inside the upstream fixed
#    test_axes.py that /opt/golden also carries.
if ! ( cd / && python3 - <<'EOF' > /tmp/golden_provenance.out 2>&1
import ast
import sys

stand = open("/opt/golden/test_hist_timedelta_raises.py", encoding="utf-8").read()
fixed = open("/opt/golden/test_axes_fixed.py", encoding="utf-8").read()


def body_of(src, name):
    tree = ast.parse(src)
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return ast.get_source_segment(src, node)
    raise SystemExit("function not found")

b1 = body_of(stand, "test_hist_timedelta_raises")
b2 = body_of(fixed, "test_hist_timedelta_raises")
assert b1 == b2, "golden body mismatch"
assert "does not currently support timedelta inputs" in b1
print("golden provenance OK")
sys.exit(0)
EOF
)
then
    cat /tmp/golden_provenance.out >> "$LOG"
    fail "planted golden test is not byte-identical to the upstream regression test (see $LOG)"
fi
rm -rf /tmp/gtest && mkdir -p /tmp/gtest
cp /opt/golden/test_hist_timedelta_raises.py /tmp/gtest/ || fail "cannot plant golden test"
( cd /tmp/gtest && python3 -m pytest test_hist_timedelta_raises.py -q -p no:cacheprovider \
      > /tmp/golden_fixed.out 2>&1 )
rc=$?
if [ "$rc" -ne 0 ]; then
    tail -20 /tmp/golden_fixed.out >&2
    fail "upstream regression test did not pass on the repaired tree (see /tmp/golden_fixed.out)"
fi
grep -q "1 passed" /tmp/golden_fixed.out || fail "golden test did not actually run and pass (see /tmp/golden_fixed.out)"
( cd /tmp/gtest && MESONPY_EDITABLE_SKIP=$PIX PYTHONPATH=/opt/prefix/lib \
      python3 -m pytest test_hist_timedelta_raises.py -q -p no:cacheprovider \
      > /tmp/golden_prefix.out 2>&1 )
rc=$?
if [ "$rc" -eq 0 ]; then
    tail -20 /tmp/golden_prefix.out >&2
    fail "upstream regression test unexpectedly PASSED against the pre-fix concept (see /tmp/golden_prefix.out)"
fi
grep -qE "FAILED|AssertionError|DID NOT RAISE" /tmp/golden_prefix.out \
    || fail "pre-fix golden run failed for the wrong reason (see /tmp/golden_prefix.out)"

# 7) a targeted slice of the project's OWN existing test suite covering the
#    same histogram machinery must stay green on the repaired tree.
( cd /app/src && python3 -m pytest \
    lib/matplotlib/tests/test_axes.py::test_hist_float16 \
    lib/matplotlib/tests/test_axes.py::test_hist_unequal_bins_density \
    lib/matplotlib/tests/test_axes.py::test_hist_single_color_multiple_datasets \
    lib/matplotlib/tests/test_axes.py::test_hist2d_density \
    lib/matplotlib/tests/test_axes.py::test_hist2d_autolimits \
    lib/matplotlib/tests/test_axes.py::test_hist_step_geometry \
    lib/matplotlib/tests/test_axes.py::test_hist_step_bottom_geometry \
    lib/matplotlib/tests/test_axes.py::test_hist_stacked_step_geometry \
    lib/matplotlib/tests/test_axes.py::test_hist_stacked_step_bottom_geometry \
    lib/matplotlib/tests/test_axes.py::test_hist_barstacked_bottom_unchanged \
    lib/matplotlib/tests/test_axes.py::test_hist_emptydata \
    lib/matplotlib/tests/test_axes.py::test_hist_unused_labels \
    lib/matplotlib/tests/test_axes.py::test_hist_labels \
    lib/matplotlib/tests/test_axes.py::test_length_one_hist \
    lib/matplotlib/tests/test_axes.py::test_numerical_hist_label \
    lib/matplotlib/tests/test_axes.py::test_unicode_hist_label \
    lib/matplotlib/tests/test_axes.py::test_hist_auto_bins \
    lib/matplotlib/tests/test_axes.py::test_hist_nan_data \
    lib/matplotlib/tests/test_axes.py::test_hist_range_and_density \
    lib/matplotlib/tests/test_axes.py::test_hist_with_empty_input \
    lib/matplotlib/tests/test_axes.py::test_hist_zorder \
    -q -p no:cacheprovider > /tmp/existing.out 2>&1 )
rc=$?
if [ "$rc" -ne 0 ]; then
    tail -30 /tmp/existing.out >&2
    fail "project's existing hist tests failed on the repaired tree (see /tmp/existing.out)"
fi
grep -q "25 passed" /tmp/existing.out || fail "existing-suite slice did not run all 25 nodes (see /tmp/existing.out)"

# 8) authored hidden cases: other timedelta64 units/shapes, python timedelta
#    with histogram parameters, multi-dataset calls, numeric unaffected.
CASES=0
for case in /tests/hidden/*/; do
    name=$(basename "$case")
    [ -f "$case/run.py" ] || fail "hidden case $name: missing run.py"
    if ! python3 "$case/run.py" > /tmp/hc-$name.out 2>&1; then
        echo "hidden case $name failed on the repaired tree; stdout:" >> "$LOG"
        head -12 /tmp/hc-$name.out >> "$LOG"
        fail "hidden case $name: assertion failed (see $LOG)"
    fi
    marker=$(grep -Eo '^H[0-9] [A-Z0-9 ]*OK' /tmp/hc-$name.out | head -1)
    if [ -z "$marker" ]; then
        echo "hidden case $name printed no PASS marker; stdout:" >> "$LOG"
        head -12 /tmp/hc-$name.out >> "$LOG"
        fail "hidden case $name: missing PASS marker (see $LOG)"
    fi
    echo "hidden case $name: $marker" >> "$LOG"
    CASES=$((CASES + 1))
done
[ "$CASES" -ge 4 ] || fail "only $CASES hidden case(s) ran; expected 4"

echo "PASS: integrity, provenance, deliverables, repro both directions, independent probe both directions, upstream regression test both directions, existing suite slice, all hidden cases"
echo 1 > /logs/verifier/reward.txt
exit 0