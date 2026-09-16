#!/bin/bash
# Verifier for capstan-rudder: an upstream-clone debugging task on librosa.
#
# The agent must repair, in the real checkout at /app/src, a real upstream
# bug: midi_to_note / midi_to_svara_h / midi_to_svara_c raise
# ValueError/OverflowError on non-finite pitch values and note_to_midi("")
# raises ParameterError, where the fixed library returns "" / np.nan. The
# verifier:
#   0. asserts environment + tree provenance: the python tree
#      (/usr/local/lib/python3.12 incl. site-packages), /usr/local/bin and
#      /opt/golden are byte-identical to their build-time snapshots (no
#      sitecustomize/.pth hook, no tampered stdlib module, no edited
#      golden test or conftest); HEAD is still the pinned parent commit;
#      the upstream fix commit is not reachable from the clone; the
#      imported librosa resolves to /app/src; git status shows exactly one
#      modified source file;
#   1. runs the golden file -- the project's own tests/test_convert.py as of
#      the fix commit, i.e. the 10 upstream regression cases plus the
#      module's full pre-existing suite -- with the project's own test
#      runner (pytest) from the repaired tree. The interpreter runs with
#      python -S (no site processing: sitecustomize/usercustomize/.pth are
#      inert) and pytest is pinned to the harness-owned /opt/golden
#      (--rootdir/--confcutdir), so the only code that can make the suite
#      pass is the deliverable tree itself;
#   2. runs two authored hidden-case drivers over scalar/kwargs and
#      vectorised/list inputs the upstream regression tests do not use.
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1
export PYTHONPATH=/app/src:/usr/local/lib/python3.12/site-packages

SRC=/app/src
PARENT_SHA=86d728a4fae31c5e80ef112f895c70af228d1637
FIX_SHA=025ef7d1c7ad6d8593b959c41bf12eb7c945c6eb
GOLDEN=/opt/golden/test_convert_fix.py
GOLDEN_SHA=1e667700400a090ff6e63d1ae196f89070abc1745c3581a58dd4a0192b566c99

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0a. environment integrity (build-time snapshots) -----------------
echo "== environment integrity =="
check_manifest() {  # check_manifest NAME DIR
  local name="$1" dir="$2"
  if LC_ALL=C find "$dir" \( -type f -o -type l \) ! -path '*/__pycache__/*' -print 2>/dev/null \
       | LC_ALL=C sort | xargs -r -d '\n' sha256sum \
       | cmp -s - "/opt/manifests/$name.sha"; then
    echo "ok: $name tree matches the build-time snapshot"
  else
    fail "$name tree differs from the build-time snapshot (added/tampered files outside /app/src):"
    LC_ALL=C find "$dir" \( -type f -o -type l \) ! -path '*/__pycache__/*' -print 2>/dev/null \
      | LC_ALL=C sort | xargs -r -d '\n' sha256sum 2>/dev/null \
      | diff "/opt/manifests/$name.sha" - 2>/dev/null \
      | head -8 | sed 's/^/    /' >&2
  fi
}
if [ -f /opt/manifests/pylib.sha ] && [ -f /opt/manifests/bin.sha ] && [ -f /opt/manifests/golden.sha ]; then
  check_manifest pylib /usr/local/lib/python3.12
  check_manifest bin /usr/local/bin
  check_manifest golden /opt/golden
else
  fail "build-time environment snapshots missing (/opt/manifests)"
fi

# ---------- 0b. tree provenance ---------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

imp=$(python3 -S -c "import librosa; print(librosa.__file__)" 2>/dev/null || true)
case "$imp" in
  /app/src/librosa/*) echo "ok: imported librosa comes from the deliverable tree ($imp)" ;;
  *) fail "imported librosa is not the deliverable tree (got: ${imp:-nothing})" ;;
esac

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
if [ -z "$porcelain" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
elif [ "$porcelain" = " M librosa/core/convert.py" ]; then
  echo "ok: working tree differs from the pinned commit only in librosa/core/convert.py"
else
  fail "unexpected working-tree changes:"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

tree_golden=$(sha256sum < "$GOLDEN" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_golden" = "$GOLDEN_SHA" ]; then
  echo "ok: golden regression file is byte-identical to the upstream fix-commit tests/test_convert.py"
else
  fail "golden regression file altered or missing (${tree_golden:-missing})"
fi

# ---------- 1. the project's own conversion-module suite ----------------------
echo "== the project's own suite (tests/test_convert.py at the fix commit, incl. the 10 upstream regressions) =="
if [ "$reward" = 1 ]; then
  if ( cd / && python3 -S -m pytest -p no:cacheprovider -o addopts='' --rootdir=/opt/golden --confcutdir=/opt/golden -v "$GOLDEN" > /tmp/golden.out 2>&1 ); then
    echo "ok: module suite exits 0 (all pre-existing + regression tests pass)"
  else
    fail "module suite does not exit 0; tail of run:"
    tail -15 /tmp/golden.out | sed 's/^/    /' >&2
  fi
fi

echo "== upstream regression cases pass =="
if [ "$reward" = 1 ]; then
  n_missing=0
  for name in test_midi_to_note_empty test_midi_to_svara_h_empty \
              test_midi_to_svara_c_empty test_note_to_midi_empty; do
    if grep -qE "${name}(\[[^]]*\])? PASSED" /tmp/golden.out 2>/dev/null; then
      echo "ok: golden case passes: $name"
    else
      echo "FAIL: golden case did not pass: $name" >&2
      n_missing=$((n_missing + 1))
    fi
  done
  if [ "$n_missing" -gt 0 ]; then
    reward=0
  fi
fi

# ---------- 2. authored hidden cases -----------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  cname=$(basename "$case")
  run="$case/run.py"
  if [ ! -f "$run" ]; then
    fail "hidden case $cname has no run.py"
    continue
  fi
  if out=$(python3 -S "$run" 2>&1); then
    echo "ok: hidden case $cname: $(echo "$out" | tail -1)"
  else
    fail "hidden case $cname"
    printf '%s\n' "$out" | tail -8 | sed 's/^/    /' >&2
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0