#!/bin/bash
# Verifier for pintle-flint: an upstream-clone debugging task on scikit-image.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# skimage.measure.regionprops keeps its private cache populated even when
# caching is disabled (cache=False), so region objects retain every computed
# property (binary masks, intensity crops, ...) for their lifetime. The agent
# must author its own failing reproduction at /app/repro.py (deliverable) and
# repair the source tree.
#
#   0. tree provenance: HEAD is still the pinned parent commit, the upstream
#      fix commit is not reachable from the working clone, exactly one tracked
#      source file (skimage/measure/_regionprops.py) is modified, no staged or
#      untracked files appeared in the clone, and /app/repro.py exists;
#   0.5 interpreter/library hygiene: no sitecustomize/usercustomize anywhere
#      on sys.path, editable-install pth/loader byte-pinned, /opt/golden
#      byte-pinned, no shadow 'skimage' package outside the clone, and the
#      skimage.measure._regionprops module the verifier imports resolves to
#      /app/src;
#   1. the upstream regression test for this bug, extracted at image build
#      time from the fix commit into /opt/golden/, passes on the repaired
#      tree;
#   2. the agent's own reproduction exits 0 on the repaired tree;
#   3. the agent's own reproduction and the golden test are run against the
#      PRE-FIX tree (the single tracked change is stashed, so the tree is
#      exactly the parent again) and must FAIL there, proving the reproduction
#      really discriminates the bug; the fix is then restored;
#   4. authored hidden cases (3-D volume; multi-region 2-D image with holes
#      and float intensities) pass on the repaired tree;
#   5. the project's own existing regionprops test module stays green.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
# Disable user-site import injection: a usercustomize.py dropped in a writable
# user HOME must never be able to supply the expected behaviour on the
# verifier's own python processes. PYTHONPATH is cleared so an agent-injected
# directory is never searched either.
export PYTHONNOUSERSITE=1
export PYTHONPATH=
mkdir -p /logs/verifier
reward=1

SRC=/app/src
REPRO=/app/repro.py
PARENT_SHA=9107d523a899b8d3767630941ac28f438bf875d2
FIX_SHA=119a89bc10801dd4c4557b007e97c79a06f9d24c
GOLDEN=/opt/golden/test_regionprops.py
PTH=/usr/local/lib/python3.12/site-packages/scikit-image-editable.pth
LOADER=/usr/local/lib/python3.12/site-packages/_scikit_image_editable_loader.py
PTH_SHA=7dae6f45a746f9d783384abc718a4c9b508211d1783ecc5b892f44de0bdf7227
LOADER_SHA=abceefa0790da4519d68bf6f0f669570bad7201e8862be26c8d84091532a4266
GOLDEN_SHA=863cec292e73905f3eca03a5fc6912f1d7258d2ed8d8defdd43b17e11ef26a8c

run_pytest () {  # run_pytest LABEL OUT ...args ; runs pytest from $SRC
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && python3 -m pytest "$@" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -40 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

clear_pyc () {
  find "$SRC" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  echo "FAIL: /app/src is not a git clone" >&2; reward=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
# The working tree must contain EXACTLY one change: an unstaged edit of
# skimage/measure/_regionprops.py. Anything else fails provenance: other
# modified tracked files, staged changes, typechanges, and any untracked file
# (a steering conftest.py, a patched-in helper, ...) can supply the expected
# behaviour while the buggy code is left in place.
bad=$(printf '%s\n' "$porcelain" | grep -v '^ M skimage/measure/_regionprops.py$' || true)
if [ -n "$porcelain" ] && [ -n "$bad" ]; then
  echo "FAIL: working tree must contain exactly one change, an unstaged edit of skimage/measure/_regionprops.py:" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- skimage/measure/_regionprops.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

if [ ! -f "$REPRO" ] || [ ! -s "$REPRO" ]; then
  echo "FAIL: deliverable /app/repro.py is missing or empty" >&2
  reward=0
else
  echo "ok: /app/repro.py present"
fi

# ---------- 0.5 interpreter/library hygiene -----------------------------------
# The agent phase runs as root in this same filesystem, so every fix that the
# scored behaviours below accept could in principle have been layered in
# without touching the scored code: a sitecustomize.py on sys.path, a rewrite
# of the editable-install pth/loader (or a shadow 'skimage' package dropped in
# site-packages), a rewrite of the golden test (or a conftest.py seeded next to
# it), or a stub of the guard text in the source while a wrapper supplies the
# behaviour. All of those are rejected here.
echo "== interpreter hygiene =="
hygiene_ok=1
# (a) no sitecustomize.py / usercustomize.py anywhere on the interpreter path
if python3 - 2>/tmp/hygiene.err > /tmp/hygiene.out <<'PY'
import sys, pathlib
hits = []
for base in sys.path:
    if not base:
        continue
    p = pathlib.Path(base)
    if not p.is_dir():
        continue
    for name in ("sitecustomize.py", "usercustomize.py"):
        f = p / name
        if f.exists():
            hits.append(str(f))
sys.stdout.write("\n".join(hits))
PY
then
  if [ -s /tmp/hygiene.out ]; then
    echo "FAIL: import-time hook file(s) found on sys.path (the fix must be in the tracked source):" >&2
    sed 's/^/    /' /tmp/hygiene.out >&2
    hygiene_ok=0
  fi
else
  echo "FAIL: could not inspect the interpreter sys.path" >&2
  hygiene_ok=0
fi
# (b) the editable-install pth and loader must still be the build-time files
pth_sha=$(sha256sum "$PTH" 2>/dev/null | cut -d' ' -f1)
loader_sha=$(sha256sum "$LOADER" 2>/dev/null | cut -d' ' -f1)
if [ "$pth_sha" != "$PTH_SHA" ] || [ "$loader_sha" != "$LOADER_SHA" ]; then
  echo "FAIL: editable-install pth/loader differs from the build-time files (an import hook was injected)" >&2
  echo "    pth=$pth_sha loader=$loader_sha" >&2
  hygiene_ok=0
fi
# (c) no shadow 'skimage' package/dir outside the clone (site-packages)
if [ -d /usr/local/lib/python3.12/site-packages/skimage ] \
   || ls -d /usr/local/lib/python3.12/site-packages/skimage-* 2>/dev/null | grep -q . ; then
  echo "FAIL: a shadow 'skimage' directory exists in site-packages" >&2
  hygiene_ok=0
fi
# (d) the golden directory holds exactly the pinned fix-commit test file
if [ "$(sha256sum "$GOLDEN" 2>/dev/null | cut -d' ' -f1)" != "$GOLDEN_SHA" ]; then
  echo "FAIL: $GOLDEN differs from the fix-commit regression test (it was rewritten, not implemented)" >&2
  hygiene_ok=0
fi
extra=$(find /opt/golden -maxdepth 1 -type f ! -name test_regionprops.py 2>/dev/null)
if [ -n "$extra" ]; then
  echo "FAIL: unexpected additional file(s) in /opt/golden:" >&2
  echo "$extra" | sed 's/^/    /' >&2
  hygiene_ok=0
fi
if [ "$hygiene_ok" = 0 ]; then
  reward=0
else
  echo "ok: interpreter hygiene (no import hooks, editable install pinned, golden pinned)"
fi

# ---------- 0.6 the module under test resolves to the tracked tree ------------
echo "== module origin =="
if python3 - > /tmp/origin.out 2>&1 <<'PY'
import inspect, pathlib
import skimage.measure  # noqa: F401
import skimage.measure._regionprops as rp
src = str(pathlib.Path(inspect.getsourcefile(rp)).resolve())
assert src.startswith("/app/src/"), src
print("ok:", src)
PY
then
  cat /tmp/origin.out
else
  echo "FAIL: skimage.measure._regionprops does not resolve to the tracked /app/src tree (a shadow copy supplies the behaviour)" >&2
  tail -20 /tmp/origin.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 1. golden test on the repaired tree -------------------------------
echo "== golden test on the repaired tree =="
run_pytest "golden test_disabled_cache_is_empty" /tmp/golden.out \
  "$GOLDEN::test_disabled_cache_is_empty" || true

# ---------- 2. the agent's own reproduction on the repaired tree --------------
echo "== agent reproduction on the repaired tree =="
if ( cd "$SRC" && python3 "$REPRO" > /tmp/repro-fixed.out 2>&1 ); then
  echo "ok: /app/repro.py exits 0 on the repaired tree ($(tail -1 /tmp/repro-fixed.out))"
else
  echo "FAIL: /app/repro.py must exit 0 on the repaired tree" >&2
  tail -20 /tmp/repro-fixed.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 2.5 cache=False retains NOTHING anywhere (not just _cache) --------
# A fake 'fix' can keep the memory-retention bug and still satisfy `_cache == {}`
# by routing cache=False values through a RENAMED private stash (_stash) and
# serving them back from there: the region object then keeps holding every
# computed array exactly as before, while every check that only looks at
# `_cache` passes. Two name-agnostic checks close that shape:
#   (a) after a spread of reads, the region object must not have GAINED any
#       attribute (a stash attribute can only appear if values are retained);
#   (b) a second read of an array-valued property must return a DIFFERENT
#       object (under the fix, cache=False recomputes and returns a fresh
#       f(obj) every time; a retained value returns the same object).
echo "== cache=False retention/freshness (name-agnostic) =="
if python3 - > /tmp/fresh.out 2>&1 <<'PY'
import numpy as np
from skimage.measure import regionprops
label = np.zeros((24, 24), dtype=int)
label[3:10, 2:9] = 1
label[15:20, 15:22] = 2
intensity = np.random.default_rng(1).random(label.shape)
r = regionprops(label, intensity_image=intensity, cache=False)[0]
before = set(vars(r))
for name in ("area", "bbox", "image", "image_filled", "image_convex",
             "area_convex", "inertia_tensor", "area_filled", "solidity",
             "eccentricity", "axis_major_length", "euler_number",
             "intensity_mean", "centroid_weighted"):
    getattr(r, name)
after = set(vars(r))
new_attrs = after - before
if new_attrs:
    raise SystemExit("cache=False created retained attributes: %s" % sorted(new_attrs))
if not (r._cache == {}):
    raise SystemExit("cache=False retained %d cached properties" % len(r._cache))
a = r.image_filled
b = r.image_filled
if a is b:
    raise SystemExit("cache=False second read returned the same object (values were retained, not recomputed)")
print("ok: cache=False retains nothing and recomputes fresh values")
PY
then
  cat /tmp/fresh.out
else
  echo "FAIL: cache=False retention/freshness check" >&2
  tail -20 /tmp/fresh.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 3. pre-fix tree legs (repro and golden must FAIL) -----------------
echo "== pre-fix tree legs =="
if git -C "$SRC" diff --quiet -- skimage/measure/_regionprops.py; then
  echo "FAIL: cannot run the pre-fix legs: skimage/measure/_regionprops.py is unchanged" >&2
  reward=0
else
  if git -C "$SRC" stash push -q -- skimage/measure/_regionprops.py; then
    :
  else
    echo "FAIL: git stash failed" >&2
    reward=0
  fi
  clear_pyc
  if git -C "$SRC" diff --quiet -- skimage/measure/_regionprops.py; then
    echo "ok: fix momentarily reverted (tree is the parent again)"
    python3 "$REPRO" > /tmp/repro-prefix.out 2>&1
    rc=$?
    if [ $rc -eq 0 ]; then
      echo "FAIL: /app/repro.py exits 0 against the PRE-FIX tree (it does not discriminate the bug)" >&2
      tail -20 /tmp/repro-prefix.out | sed 's/^/    /' >&2
      reward=0
    else
      echo "ok: /app/repro.py fails on the pre-fix tree (rc=$rc)"
    fi
    if ( cd "$SRC" && python3 -m pytest "$GOLDEN::test_disabled_cache_is_empty" -q -p no:cacheprovider > /tmp/golden-prefix.out 2>&1 ); then
      echo "FAIL: golden test PASSES against the pre-fix tree" >&2
      tail -20 /tmp/golden-prefix.out | sed 's/^/    /' >&2
      reward=0
    else
      echo "ok: golden test fails on the pre-fix tree"
    fi
  else
    echo "FAIL: could not revert skimage/measure/_regionprops.py to the pre-fix state" >&2
    reward=0
  fi
  if git -C "$SRC" stash pop -q; then
    :
  else
    echo "FAIL: could not restore the agent's fix after the stash round-trip" >&2
    reward=0
  fi
  clear_pyc
  if git -C "$SRC" diff --quiet -- skimage/measure/_regionprops.py; then
    echo "FAIL: the agent's fix was lost in the stash round-trip" >&2
    reward=0
  fi
fi

# ---------- 4. hidden cases ----------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && python3 "$case/check.py" > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2
  reward=0
fi

# ---------- 5. the project's own existing regionprops suite --------------------
echo "== the project's own existing regionprops tests =="
run_pytest "existing skimage/measure/tests/test_regionprops.py" /tmp/own.out \
  skimage/measure/tests/test_regionprops.py || true

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0