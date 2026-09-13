#!/bin/bash
# Verifier for ballast-keel: an upstream-clone debugging task on librosa.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# librosa.note_to_hz silently quantizes any note spelling that carries a
# cents tuning deviation (e.g. 'C2-30') to the nearest equal-tempered
# semitone, returning exactly the plain note's frequency. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, exactly one commit exists, the
#      only modified tracked file is librosa/core/convert.py, no tracked
#      test file was doctored, and `import librosa` resolves to the checked
#      out tree);
#   1. copies in the project's own regression test for this bug, extracted
#      at image build time from the fix commit into /opt/golden/, and
#      requires it to pass against the agent's repaired tree (it fails
#      against the parent tree: the image build asserts that);
#   2. runs the project's own existing test suite (tests/test_convert.py in
#      full) to prove the fix broke nothing else;
#   3. runs the exact issue reproduction command from the instruction;
#   4. runs three authored hidden cases: single deviated notes across
#      octaves/accidentals/flats (case-1-deviated-notes), list-typed mixed
#      deviated/plain inputs (case-2-list-input), and the round_midi=True
#      quantization path plus the default==round_midi=False identity
#      (case-3-round-midi-option). Every expectation is computed from the
#      independent formula 440 * 2 ** ((midi - 69) / 12), not from the
#      library under test.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=a0d0374370183d93ad7a4a348da034ab5b3e1687
FIX_SHA=86d728a4fae31c5e80ef112f895c70af228d1637
GOLDEN=/opt/golden/test_convert.py
GOLDEN_SHA=3b5b30a5adb54fb8ed39a86073d7ec906e0f8071497dd5db576591ceac5beb97

export PYTHONDONTWRITEBYTECODE=1

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

run_pytest () {  # run_pytest LABEL OUT ...args  (cwd = SRC)
  label="$1"; out="$2"; shift 2
  # lazy_loader>=0.4 can break pytest collection of librosa's own tests
  # ('No librosa.core attribute convert': tests/test_convert.py reads
  #   librosa.core.convert.WEIGHTING_FUNCTIONS at import time); running
  # pytest through this wrapper pre-imports librosa.core.convert in the
  # same process, which fixes collection.
  if ( cd "$SRC" && python3 -c "import sys, librosa.core.convert, pytest; sys.exit(pytest.main(list(sys.argv[1:])))" "$@" -o addopts= -p no:cacheprovider > "$out" 2>&1 ); then
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

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" != "1" ]; then
  fail "the working clone contains $ncommits commits; it must contain exactly the pinned parent commit"
else
  echo "ok: exactly one commit object reachable in the working clone"
fi

saw_mod=0
bad_tree=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M librosa/core/convert.py")
      saw_mod=1
      ;;
    " M "*) # modified tracked file outside the fix target
      echo "FAIL: a tracked file other than librosa/core/convert.py was modified: $line" >&2
      bad_tree=1
      ;;
    " D "*) echo "FAIL: a tracked file was deleted: $line" >&2; bad_tree=1 ;;
    "?? "*) # untracked files allowed anywhere except the package and the tests
      case "$line" in
        "?? librosa/core/"*|"?? tests/"*)
          echo "FAIL: a new file was added inside librosa/core/ or tests/: $line" >&2
          bad_tree=1 ;;
        *) : ;;
      esac
      ;;
    *) echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$bad_tree" = 1 ]; then reward=0; else echo "ok: no unexpected working-tree changes"; fi
if [ "$saw_mod" = 0 ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: librosa/core/convert.py differs from the pinned commit"
fi

if ! ( cd / && python3 -c "import librosa; import sys; sys.exit(0 if librosa.__file__ == '$SRC/librosa/__init__.py' else 3)" >/dev/null 2>&1 ); then
  fail "'import librosa' does not resolve to the checked-out tree at /app/src"
else
  echo "ok: import librosa resolves to $SRC/librosa/__init__.py"
fi

# ---------- 1. golden: the upstream regression test for this bug --------------
echo "== golden test (the project's own regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  fail "golden test missing from image"
  reward=0
else
  sha=$(sha256sum < "$GOLDEN" | cut -d' ' -f1)
  if [ "$sha" != "$GOLDEN_SHA" ]; then
    fail "golden test in image has unexpected hash $sha"
    reward=0
  else
    echo "ok: /opt/golden/test_convert.py is the fix-commit regression file (sha $GOLDEN_SHA)"
    cp "$GOLDEN" "$SRC/tests/test_convert.py"
    run_pytest "golden test_note_to_hz_default" /tmp/golden.out \
      "tests/test_convert.py::test_note_to_hz_default" || true
  fi
fi

# ---------- 2. the project's own existing test suite --------------------------
echo "== the project's own existing test suite (tests/test_convert.py) =="
run_pytest "tests/test_convert.py in full" /tmp/own.out tests/test_convert.py || true

# ---------- 3. the exact issue reproduction command ---------------------------
echo "== issue reproduction =="
if [ "$reward" = 1 ] && ( cd "$SRC" && python3 -c "
import librosa
h = librosa.note_to_hz('C2-30')
print('note_to_hz(C2-30) =', repr(h))
print('note_to_hz(C2)    =', repr(librosa.note_to_hz('C2')))
assert h != librosa.note_to_hz('C2')
" > /tmp/repro.out 2>&1 ); then
  echo "ok: note_to_hz('C2-30') differs from note_to_hz('C2')"
  sed 's/^/    /' /tmp/repro.out
else
  fail "the issue reproduction still asserts (note_to_hz('C2-30') == note_to_hz('C2'))"
  tail -10 /tmp/repro.out 2>/dev/null | sed 's/^/    /' >&2 || true
fi

# ---------- 4. authored hidden cases -----------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  for f in "$case"test_*.py; do
    [ -f "$f" ] || continue
    n_hidden=$((n_hidden + 1))
    name=$(basename "$(dirname "$f")")/$(basename "$f")
    out="/tmp/hidden-${n_hidden}.out"
    if python3 "$f" > "$out" 2>&1; then
      echo "ok: hidden case $name"
      tail -2 "$out" | sed 's/^/    /'
    else
      fail "hidden case $name"
      tail -15 "$out" | sed 's/^/    /' >&2
    fi
  done
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0