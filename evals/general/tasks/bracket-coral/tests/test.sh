#!/bin/bash
# Verifier for bracket-coral: an upstream-clone debugging task on pallets/werkzeug.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the streaming multipart decoder returns corrupted file bytes for uploads whose
# content ends with newline bytes at the point where the part's closing boundary
# arrives (extra CR/LF bytes leak into the file). The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, no
#      fetched commits are reachable, only the minimal tracked source file is
#      modified, and no new files appeared inside the werkzeug package);
#   1. runs the project's own regression test for this bug, extracted at image
#      build time from the fix commit into /opt/golden/;
#   2. runs the project's own existing multipart, form-parser and wrapper tests
#      from the tree, proving the fix broke nothing else;
#   3. runs two authored hidden-case suites (chunked low-level decoding with
#      different boundaries/file bytes, and an end-to-end upload through the
#      project's own form parser with a small read buffer) that the upstream
#      regression test does not cover.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=2a2e371f41aba5d83ca575e65a6409aaa7dc1097
FIX_SHA=89ce5e5a4c59bc9d51d360fd5c205b344ecf06c8
GOLDEN=/opt/golden/test_multipart.py
GOLDEN_SHA256=5fa511606269e02e3e01975da0414a08d12df22f23e705fbee16fc4267ac17b0
MULTIPART_SRC=src/werkzeug/sansio/multipart.py

run_pytest () {  # run_pytest LABEL OUT ...args
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
bad=$(printf '%s\n' "$porcelain" | grep -v "^ M $MULTIPART_SRC$" | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only $MULTIPART_SRC may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? src/werkzeug/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the werkzeug package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- "$MULTIPART_SRC" 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 0.5 harness-owned files must be untouched --------------------------
# /opt/golden lives inside the image and is not re-uploaded at verify time, so
# an agent running as root could replace the upstream regression test with a
# passing stub (or plant a conftest.py that redefines it) instead of fixing the
# bug. Guard the exact upstream bytes with a hash and forbid anything else in
# the directory (pytest __pycache__ dirs are expected and allowed).
if [ -f "$GOLDEN" ]; then
  actual=$(sha256sum "$GOLDEN" | awk '{print $1}')
  if [ "$actual" != "$GOLDEN_SHA256" ]; then
    echo "FAIL: $GOLDEN was modified (sha256 $actual != $GOLDEN_SHA256)" >&2
    reward=0
  else
    echo "ok: golden test bytes match the upstream fix revision"
  fi
  unexpected=$(find /opt/golden -mindepth 1 -not -name test_multipart.py | grep -vE '(__pycache__(/|$)|/[^/]*\.pyc$)' || true)
  if [ -n "$unexpected" ]; then
    echo "FAIL: unexpected files in /opt/golden:" >&2
    printf '%s\n' "$unexpected" | head -5 | sed 's/^/    /' >&2
    reward=0
  fi
else
  echo "FAIL: golden test missing from image" >&2
  reward=0
fi

# The verdict must be computed on the checked-out tree's own code: the module
# that gets imported and tested must be the deliverable at /app/src, not a copy
# the agent installed or pointed at elsewhere.
imported=$(PYTHONPATH= python3 -c 'import os, werkzeug.sansio.multipart as m; print(os.path.realpath(m.__file__))' 2>/dev/null || true)
case "$imported" in
  "$SRC"/*) echo "ok: werkzeug.sansio.multipart imports from $imported" ;;
  *) echo "FAIL: werkzeug.sansio.multipart imports from '$imported', not the deliverable tree" >&2; reward=0 ;;
esac

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  run_pytest "golden /opt/golden/test_multipart.py" /tmp/golden.out "$GOLDEN" \
    || true
fi

# ---------- 2. the project's own existing tests -------------------------------
echo "== the project's own existing tests =="
run_pytest "existing tests/sansio/test_multipart.py" /tmp/own-multipart.out tests/sansio/test_multipart.py \
  || true
run_pytest "existing tests/test_formparser.py" /tmp/own-formparser.out tests/test_formparser.py \
  || true
run_pytest "existing tests/test_wrappers.py" /tmp/own-wrappers.out tests/test_wrappers.py \
  || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd "$SRC" && python3 -m pytest "$case" -q -p no:cacheprovider > "$out" 2>&1 ); then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -40 "$out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0