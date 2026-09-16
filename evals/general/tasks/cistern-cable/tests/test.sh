#!/bin/bash
# Verifier for cistern-cable: an upstream-clone debugging task on httpx.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# iterating the decoded text of a streamed response body yields a spurious
# trailing empty string.  The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      minimal tracked source files are modified, and no new files appeared
#      inside the package);
#   1. runs the project's own regression test for this bug, extracted at image
#      build time from the fix commit into /opt/golden/;
#   2. runs the project's own existing decoder and response-iteration suites
#      from the tree, proving the fix broke nothing else;
#   3. runs three authored hidden cases (UTF-8 split across chunk boundaries
#      plus single-piece streams, empty chunks inside the stream, and the
#      async aiter_text path) that the upstream test does not cover.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=90538a3b4610ba49ce16c997bcfdb9101f9503be
FIX_SHA=1e110964736a95d822144390b99d7ecf17fca527
GOLDEN=/opt/golden/test_decoders.py
PTCFG="$SRC/pyproject.toml"

run_pytest () {  # run_pytest LABEL OUT ...args
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && PYTHONDONTWRITEBYTECODE=1 python3 -m pytest "$@" > "$out" 2>&1 ); then
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
bad=$(printf '%s\n' "$porcelain" \
  | grep -v '^ M httpx/_decoders.py$' \
  | grep -v '^ M httpx/_models.py$' \
  | grep -v '^?? ' || true)
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree changes (only httpx/_decoders.py and httpx/_models.py may be modified):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
newpkg=$(printf '%s\n' "$porcelain" | grep '^?? httpx/' || true)
if [ -n "$newpkg" ]; then
  echo "FAIL: new files were added inside the httpx package:" >&2
  printf '%s\n' "$newpkg" | head -5 | sed 's/^/    /' >&2
  reward=0
fi

# An untracked conftest.py at the pytest rootdir is auto-loaded and can patch
# httpx at import time, faking the golden and own-suite runs without touching
# the source (the hidden cases run outside its reach, but fail closed anyway).
# sitecustomize.py / *.pth would do the same for every interpreter if a site
# dir were writable. No honest fix adds such files: any untracked import-hook
# file is a FAIL.
hookfiles=$(printf '%s\n' "$porcelain" \
  | grep '^?? ' \
  | grep -E 'conftest\.py$|sitecustomize\.py$|\.pth$' || true)
if [ -n "$hookfiles" ]; then
  echo "FAIL: untracked import-hook file added to the tree (conftest.py / sitecustomize.py / *.pth); fix the source instead:" >&2
  printf '%s\n' "$hookfiles" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- httpx/_decoders.py httpx/_models.py 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  run_pytest "golden full decoder file (incl. test_streaming_text_decoder)" \
    /tmp/golden.out -c "$PTCFG" "$GOLDEN" || true
fi

# ---------- 2. the project's own existing suites ------------------------------
echo "== project's own existing suites =="
run_pytest "existing tests/test_decoders.py" /tmp/own-decoders.out \
  -c "$PTCFG" tests/test_decoders.py || true

run_pytest "existing tests/models/test_responses.py (iter_text/iter_lines)" \
  /tmp/own-responses.out -c "$PTCFG" tests/models/test_responses.py -k iter \
  || true

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  out="/tmp/hidden-${name}.out"
  if ( cd /tmp && PYTHONDONTWRITEBYTECODE=1 python3 -m pytest "$case" -q -p no:cacheprovider > "$out" 2>&1 ); then
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