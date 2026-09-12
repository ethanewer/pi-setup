#!/bin/bash
# Verifier for cistern-coral. Checks, in order:
#   1. the deliverable /app/diagnosis.md exists and names operation + cause,
#   2. /app/src is the real pinned upstream clone: baseline == parent commit,
#      the fix commit is NOT reachable, the repo is shallow, and the only
#      tracked change in the working tree is the flood source file (the
#      task requires the tree to be otherwise untouched),
#   3. the INSTALLED library itself carries the fix (guards against fixing
#      pyvips instead of the C library, and proves the rebuild+install
#      actually landed),
#   4. the golden regression suite (fix-era test_draw.py, extracted into
#      /opt/golden at build time) passes against the agent's rebuilt
#      library: the full file IS the project's own draw suite plus the
#      regression test,
#   5. every hidden case in /tests/hidden/*/run.py passes: independent
#      expectations for the same code path from inputs the upstream test
#      does not use, computed in pure Python.
# Reward is binary and is written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=0
failures=0

PARENT_SHA=ea7e608844b85f4d296821e59b2483369b301b53
FIX_SHA=7cfd70a869de8fe3f3a22b32f755e382130b716c
CHANGED_FILE=libvips/draw/draw_flood.c

# ---- 1. deliverable: /app/diagnosis.md --------------------------------------
if [ ! -f /app/diagnosis.md ]; then
    echo "FAIL: deliverable /app/diagnosis.md missing" >&2
    failures=1
else
    python3 - /app/diagnosis.md <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
low = text.lower()
ok = (len(text.strip()) >= 100
      and "flood" in low
      and any(k in low for k in ("out of", "outside", "out-of-bounds", "bounds",
                                 "xsize", "ysize", "edge")))
if not ok:
    print("FAIL: /app/diagnosis.md does not name the operation and root cause "
          f"(len={len(text.strip())}, mentions flood={'flood' in low}, "
          f"mentions out-of-bounds/edge="
          f"{any(k in low for k in ('out of','outside','out-of-bounds','bounds','xsize','ysize','edge'))})", file=sys.stderr)
    sys.exit(1)
print("diagnosis: acceptable (names operation + root cause)")
PY
    rc=$?
    if [ $rc -ne 0 ]; then
        failures=1
    fi
fi

# ---- 2. provenance of the working tree --------------------------------------
if [ ! -d /app/src/.git ]; then
    echo "FAIL: /app/src is not a git working tree" >&2
    failures=1
else
    # (a) the clone is pinned to the upstream parent commit
    base=$(git -C /app/src rev-parse baseline 2>/dev/null)
    if [ "$base" != "$PARENT_SHA" ]; then
        echo "FAIL: baseline branch is $base, expected $PARENT_SHA" >&2
        failures=1
    fi
    # (b) shallow clone, i.e. the agent cannot have fetched history
    if [ "$(git -C /app/src rev-parse --is-shallow-repository 2>/dev/null)" != "true" ]; then
        echo "FAIL: clone is not shallow" >&2
        failures=1
    fi
    # (c) the fix commit must NOT be reachable from the clone
    if git -C /app/src cat-file -e "$FIX_SHA^{commit}" 2>/dev/null; then
        echo "FAIL: the upstream fix commit is present in the clone" >&2
        failures=1
    fi
    # (d) the only tracked working-tree change may be the flood source file
    changed=$(git -C /app/src diff baseline --name-only 2>/dev/null)
    if [ "$changed" != "$CHANGED_FILE" ]; then
        echo "FAIL: tracked changes vs baseline are not exactly $CHANGED_FILE:" >&2
        echo "$changed" >&2
        failures=1
    fi
    # (e) no other untracked files outside the gitignored build dir
    extra=$(git -C /app/src status --porcelain 2>/dev/null \
            | awk '{print $2}' \
            | grep -v "^$CHANGED_FILE$" \
            | grep -v '^build/' \
            | grep -v '^$' || true)
    if [ -n "$extra" ]; then
        echo "FAIL: unexpected working-tree entries:" >&2
        echo "$extra" >&2
        failures=1
    fi
    echo "provenance: pinned parent clone, fix unreachable, only $CHANGED_FILE changed"
fi

# ---- 2b. the fix must live in the C library, not in a patched binding ----
# A monkeypatched pyvips (or any edit / addition under dist-packages, incl.
# sitecustomize files) can fake every Python-visible check while the C
# library keeps silently accepting out-of-image starts. The image snapshots
# the pristine binding tree at build time (/opt/python-site.sha256, root
# only); the verifier re-hashes and fails on any change or addition. An
# honest fix (edit libvips/draw/draw_flood.c + ninja install) never touches
# it, and neither do the nop or oracle runs.
bgn=/tmp/verifier_binding_check.log
if python3 - /opt/python-site.sha256 > "$bgn" 2>&1 <<'PY'
import hashlib
import os
import sys

manifest = sys.argv[1]
expected = {}
for line in open(manifest, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line:
        continue
    h, sep, p = line.partition("  ")
    if not sep:
        continue
    p = p.strip()
    try:
        cur = hashlib.sha256(open(p, "rb").read()).hexdigest()
    except OSError:
        cur = "<missing>"
    expected[p] = (h.strip(), cur)
bad = [p for p, (h, cur) in sorted(expected.items()) if cur != h]
seen = set()
for dp, dn, fn in os.walk("/usr/local/lib/python3.12/dist-packages"):
    dn[:] = [d for d in dn if d != "__pycache__"]
    for f in sorted(fn):
        if f.endswith((".pyc", ".pyo")) or f.endswith("~"):
            continue
        seen.add(os.path.join(dp, f))
extra = sorted(seen - set(expected))
if bad or extra:
    print("binding integrity: MANIFEST MISMATCH", file=sys.stderr)
    for p in bad[:5]:
        print("  CHANGED %s (was %s.. now %s..)" %
              (p, expected[p][0][:12], expected[p][1][:12]), file=sys.stderr)
    for p in extra[:5]:
        print("  NEW %s" % p, file=sys.stderr)
    sys.exit(1)
print("binding integrity: %d files unchanged" % len(expected))
PY
then
    echo "binding integrity: python binding tree matches the build-time snapshot"
else
    echo "FAIL: installed Python binding tree differs from the pristine build-time" >&2
    echo "      snapshot; the fix must repair the C library in /app/src and rebuild it" >&2
    tail -6 "$bgn" >&2
    failures=1
fi

# ---- 3. the installed library carries the fix -------------------------------
# The task's deliverable is the repaired + rebuilt + reinstalled library, so
# the installed .so must contain the new bounds-check message. This also
# closes the loophole of "fixing" the Python binding instead of the C code.
ifs=0
for so in /usr/local/lib/x86_64-linux-gnu/libvips.so.42*; do
    [ -e "$so" ] || continue
    if strings "$so" 2>/dev/null | grep -q 'start point out of image'; then
        ifs=1
    fi
done
if [ "$ifs" = 1 ]; then
    echo "installed library: contains the draw_flood bounds-check message"
else
    echo "FAIL: installed libvips.so.42 does not contain the bounds-check message; the rebuilt library is not installed" >&2
    failures=1
fi

# ---- 4. golden regression + the project's own suite -------------------------
# Overlay the fix-era test_draw.py (parent file + the regression assertion)
# onto the tree, then run it: the full file IS the project's own draw suite,
# and it contains the new regression test. This runs before the reward is
# written, so the overlaid copy never leaks into any scoring decision.
if [ -f /opt/golden/test_draw.py ] && [ -d /app/src/test/test-suite ]; then
    cp /opt/golden/test_draw.py /app/src/test/test-suite/test_draw.py
    # the golden file must still be the fix-era upstream blob (sha256 pinned
    # in the Dockerfile at build time); tampering with it is not a fix
    if ! echo "e4b03bed7b31f5d9083833aac3123e6bd2350b7b43a21e14401b304dcccf7e10  /opt/golden/test_draw.py" \
          | sha256sum -c - > /tmp/verifier_golden_sha.log 2>&1; then
        echo "FAIL: /opt/golden/test_draw.py does not match the pinned fix-era upstream blob" >&2
        tail -3 /tmp/verifier_golden_sha.log >&2
        failures=1
    fi
    glog=/tmp/verifier_golden.log
    if (cd /app/src/test/test-suite \
        && python3 -m pytest test_draw.py -q -p no:cacheprovider > "$glog" 2>&1); then
        echo "golden draw suite (incl. regression): PASS ($(tail -1 "$glog"))"
    else
        echo "FAIL: draw test suite does not pass" >&2
        tail -25 "$glog" >&2
        failures=1
    fi
else
    echo "FAIL: golden test or test-suite directory missing" >&2
    failures=1
fi

# ---- 5. hidden cases (independent expectations, fresh inputs) ---------------
for case_dir in /tests/hidden/*/; do
    run="$case_dir/run.py"
    if [ -f "$run" ]; then
        hlog=/tmp/verifier_hidden_$(basename "$case_dir").log
        if python3 "$run" > "$hlog" 2>&1; then
            echo "hidden case $(basename "$case_dir"): PASS"
        else
            echo "FAIL: hidden case $(basename "$case_dir") failed" >&2
            tail -8 "$hlog" >&2
            failures=1
        fi
    fi
done

if [ $failures -eq 0 ]; then
    reward=1
    echo "VERIFIER: all checks passed, reward=1"
else
    echo "VERIFIER: failures present, reward=0" >&2
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0