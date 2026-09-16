#!/bin/bash
# Verifier for bracket-channel. Checks, in order:
#   1. the deliverable /app/diagnosis.md exists and names module + root cause,
#   2. /app/src is the real pinned upstream clone: baseline == parent commit,
#      the fix commit is NOT reachable, the repo is shallow, and the only
#      tracked change in the working tree is the unpremultiply source file
#      (the task requires the tree to be otherwise untouched),
#   3. the golden regression test (fix-era test_conversion.py, extracted into
#      /opt/golden at build time) passes against the agent's rebuilt library,
#   4. the project's own conversion test suite stays green (the same file,
#      run in full, is the project's own suite PLUS the regression),
#   5. every hidden case in /tests/hidden/*/run.py passes: independent
#      expectations for the same code path from inputs the upstream test
#      does not use, computed in pure Python.
# Reward is binary and is written on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
reward=0
failures=0

PARENT_SHA=92b95531d198abf9ca40aaa3f67dd6d7f4cfa2bd
FIX_SHA=dbf559add2807037d89a16b7a9e371e8267c0f63

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
      and "unpremultiply" in low
      and any(k in low for k in ("clamp", "clip", "saturat", "uchar_max", "wrap"))
      and any(k in low for k in ("8-bit", "uchar", "255")))
if not ok:
    print("FAIL: /app/diagnosis.md does not name the operation and root cause "
          f"(len={len(text.strip())}, mentions unpremultiply={'unpremultiply' in low}, "
          f"mentions clamp/clip/saturat/UCHAR_MAX/wrap="
          f"{any(k in low for k in ('clamp','clip','saturat','uchar_max','wrap'))}, "
          f"mentions 8-bit/uchar/255="
          f"{any(k in low for k in ('8-bit','uchar','255'))})", file=sys.stderr)
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
    head=$(git -C /app/src rev-parse HEAD 2>/dev/null)
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
    # (d) the only tracked working-tree change may be the unpremultiply source
    changed=$(git -C /app/src diff baseline --name-only 2>/dev/null)
    if [ "$changed" != "libvips/conversion/unpremultiply.c" ]; then
        echo "FAIL: tracked changes vs baseline are not exactly unpremultiply.c:" >&2
        echo "$changed" >&2
        failures=1
    fi
    # (e) no other untracked files outside the gitignored build dir
    extra=$(git -C /app/src status --porcelain 2>/dev/null \
            | awk '{print $2}' \
            | grep -v '^libvips/conversion/unpremultiply.c$' \
            | grep -v '^build/' \
            | grep -v '^$' || true)
    if [ -n "$extra" ]; then
        echo "FAIL: unexpected working-tree entries:" >&2
        echo "$extra" >&2
        failures=1
    fi
    echo "provenance: pinned parent clone, fix unreachable, only unpremultiply.c changed"
fi

# ---- 2g. the C source itself must implement the clamp ----------------------
# The exact buggy statement (present at the parent commit) must be gone and
# a clamp must exist in unpremultiply.c. This kills Python-site wrapper
# attacks and cosmetic edits that leave the C bug in place: the ONLY
# permitted tracked change is this file, so if the bug still lives there,
# the fix was not made where the task requires it.
srcf=/app/src/libvips/conversion/unpremultiply.c
if [ -f "$srcf" ] && grep -qF "out[i] = (in[i] * scale + 128) >> 8;" "$srcf"; then
    echo "FAIL: buggy unclamped store still present in unpremultiply.c fast path" >&2
    failures=1
elif [ -f "$srcf" ] && ! grep -qE "VIPS_MIN|VIPS_CLIP|VIPS_MAX|UCHAR_MAX|> *255|>= *255" "$srcf"; then
    echo "FAIL: unpremultiply.c contains no clamp (VIPS_MIN/VIPS_CLIP/UCHAR_MAX/255 comparison)" >&2
    failures=1
elif [ ! -f "$srcf" ]; then
    echo "FAIL: unpremultiply.c missing" >&2
    failures=1
else
    echo "source: buggy store gone, clamp present in unpremultiply.c"
fi

# ---- 2h. the installed library must actually have been rebuilt --------------
# The image ships the byte-identity of the buggy build in
# /opt/libvips-shipped.sha256; after a genuine `ninja install` of a real C
# change the installed libvips core differs from it. A container that never
# reinstalled (wrapper fakes, or a fix that is only written, not built) still
# matches the snapshot and must score 0.
if [ -f /opt/libvips-shipped.sha256 ]; then
    if sha256sum -c --status /opt/libvips-shipped.sha256 2>/dev/null; then
        echo "FAIL: installed libvips.so is byte-identical to the image-shipped" \
             "(buggy) build -- no rebuild+reinstall happened" >&2
        failures=1
    else
        echo "install: installed libvips core differs from the shipped buggy build"
    fi
else
    echo "FAIL: /opt/libvips-shipped.sha256 snapshot missing" >&2
    failures=1
fi

# ---- 3+4. golden regression + the project's own suite -----------------------
# Overlay the fix-era test_conversion.py (parent file + the regression
# assertion) onto the tree, then run it: the full file IS the project's own
# conversion suite, and it contains the new regression test.
# First verify the golden file is still the pinned upstream blob: an agent
# that edits /opt/golden to neuter the regression (root can, since the trial
# runs as root) must be caught here, not silently pass.
gold_sha=$(sha256sum /opt/golden/test_conversion.py 2>/dev/null | cut -d' ' -f1)
if [ "$gold_sha" != "1d9f925b990c6cda3f9327544038c923dcfd149923ac5199cc8e2f02113f05e4" ]; then
    echo "FAIL: /opt/golden/test_conversion.py is not the pinned upstream blob (sha256=$gold_sha)" >&2
    failures=1
fi
if [ -f /opt/golden/test_conversion.py ] && [ -d /app/src/test/test-suite ]; then
    cp /opt/golden/test_conversion.py /app/src/test/test-suite/test_conversion.py
    glog=/tmp/verifier_golden.log
    if (cd /app/src/test/test-suite \
        && python3 -m pytest test_conversion.py -q -p no:cacheprovider > "$glog" 2>&1); then
        echo "golden conversion suite (incl. regression): PASS ($(tail -1 "$glog"))"
    else
        echo "FAIL: conversion suite does not pass" >&2
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