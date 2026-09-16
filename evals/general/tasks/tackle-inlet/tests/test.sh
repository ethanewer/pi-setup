#!/bin/bash
# Verifier for tackle-inlet: an upstream-clone debugging task on nltk/nltk.
#
# Bug (upstream issue #3785): stem("") with the Hungarian flavor of NLTK's
# Snowball stemmer raises IndexError("string index out of range") from the
# r1-region detection, which reads word[0] before checking that the word is
# non-empty. The agent must fix the real checkout at /app/src and write its
# own failing reproduction at /app/reproduce.py. The verifier:
#   0. asserts tree provenance: HEAD still the pinned parent commit, the
#      upstream fix commit absent from the object store, exactly one commit
#      reachable, and the ONLY working-tree change is a non-empty
#      modification of nltk/stem/snowball.py;
#   1. asserts the installed (editable) snowball module is exactly the tree's
#      file, so no site-packages copy or import hook can stand in for a real
#      tree fix;
#   2. runs the project's own regression test -- nltk/test/unit/test_snowball.py,
#      extracted byte-for-byte from the fix release into /opt/golden -- and
#      requires all 16 language subtests to pass;
#   3. runs the data-free subset of the project's own stemmer suite
#      (nltk/test/unit/test_stem.py::SnowballTest::* and PorterTest::*) to
#      prove the fix broke nothing else;
#   4. runs three authored hidden cases (batch, edge-input, other languages)
#      driven by pytest;
#   5. executes the agent's own reproduction /app/reproduce.py twice: once
#      against a staged copy of the PRISTINE PARENT tree (it must fail --
#      proving it is a genuine reproduction of the bug) and once against the
#      repaired tree (it must exit 0 after printing the exact marker).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
REPRO=/app/reproduce.py
GOLDEN=/opt/golden/test_snowball.py
PARENT_SHA=47e236e9505c6f552d6712a21c6d960879ba7f1e
FIX_SHA=5c4c0d3fe65912fce05dae78dc76553b9e2bec85
SRCMOD="nltk/stem/snowball.py"
MARKER="OK: empty string handled"
GOLDEN_SHA="384f871f47156d369a13464e0184be9f9f095be95c5370120b18b7ef21c67eb4"

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

cd /tmp || exit 1

# Every scored python run below uses `-S` (no site module processing) with an
# explicit PYTHONPATH ("$SP" for third-party deps): sitecustomize.py, .pth
# hooks and the editable-install finder are all bypassed, so the code under
# test is the LITERAL tree bytes -- no import-time wrapper can stand in for a
# real fix in /app/src.
SP=$(python3 -c "import site; print(site.getsitepackages()[-1])") || SP=/usr/local/lib/python3.12/site-packages
echo "isolated-test site-packages: $SP"

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
bad=0

if [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" = "$PARENT_SHA" ]; then
  echo "ok: HEAD is the pinned parent commit"
else
  echo "FAIL: HEAD is not the pinned parent commit $PARENT_SHA" >&2; bad=1
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  bad=1
else
  echo "ok: fix commit not present in the working clone"
fi

ncommits=$(git -C "$SRC" rev-list --all --count 2>/dev/null || echo -)
if [ "$ncommits" = "1" ]; then
  echo "ok: exactly one commit object reachable in the working clone"
else
  echo "FAIL: the working clone has '$ncommits' reachable commits; it must contain exactly the pinned parent commit (history was fetched or added)" >&2
  bad=1
fi

saw_fix=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    " M $SRCMOD")
      saw_fix=1 ;;
    " M "*)
      echo "FAIL: a tracked file outside nltk/stem/snowball.py was modified: $line" >&2; bad=1 ;;
    " D "*)
      echo "FAIL: a tracked file was deleted: $line" >&2; bad=1 ;;
    "?? .pytest_cache/")
      # pytest cache dir is ignored; any other untracked file is a violation
      ;;
    "?? "*)
      echo "FAIL: unexpected untracked file inside the repository: $line" >&2; bad=1 ;;
    "A  "*|"M  "*|"MM "*|"D  "*|"R  "*|" C "*)
      echo "FAIL: staged or unusual working-tree entry: $line" >&2; bad=1 ;;
    *)
      echo "FAIL: unexpected working-tree change: $line" >&2; bad=1 ;;
  esac
done <<< "$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
if [ "$saw_fix" = 1 ]; then
  echo "ok: nltk/stem/snowball.py carries a modification (a fix was implemented)"
else
  echo "FAIL: no modification to nltk/stem/snowball.py (no fix implemented)" >&2
  bad=1
fi
[ "$bad" = 1 ] && reward=0

# ---------- 1. the tested module is the /app/src tree file -------------------
echo "== tested module == the /app/src tree =="
if ( cd /tmp && PYTHONPATH=/app/src:"$SP" python3 -S - <<'EOF'
import pathlib
import nltk.stem.snowball as m
inst = pathlib.Path(m.__file__).resolve()
if not str(inst).startswith("/app/src/"):
    raise SystemExit("snowball imports from outside /app/src: %s" % inst)
print("ok: with -S, import nltk.stem.snowball resolves to the tree at", inst)
EOF
); then
  :
else
  echo "FAIL: the tested nltk.stem.snowball module is not the /app/src tree file (a wrapper, sitecustomize, .pth hook or site-packages copy cannot stand in for a tree fix)" >&2
  reward=0
fi

# ---------- 2. golden: the upstream regression test ---------------------------
echo "== upstream regression test (/opt/golden/test_snowball.py) =="
if [ ! -f "$GOLDEN" ] || ! grep -q "def test_empty_string_handling" "$GOLDEN"; then
  echo "FAIL: golden regression test missing from the image" >&2
  reward=0
else
  golden_sha=$(sha256sum "$GOLDEN" | cut -d' ' -f1)
  if [ "$golden_sha" != "$GOLDEN_SHA" ]; then
    echo "FAIL: /opt/golden/test_snowball.py was altered (sha256 $golden_sha, expected $GOLDEN_SHA)" >&2
    reward=0
  else
    echo "ok: golden test file is byte-identical to the upstream release"
  fi
  if ( cd /tmp && PYTHONPATH=/app/src:"$SP" python3 -S -m pytest -v -p no:cacheprovider "$GOLDEN" ) > /tmp/golden.out 2>&1; then
    if grep -qF "1 passed, 16 subtests passed" /tmp/golden.out; then
      echo "ok: upstream regression test green -- all 16 languages handle the empty string"
    else
      echo "FAIL: golden test passed but the expected subtest count is missing from the output" >&2
      tail -30 /tmp/golden.out | sed 's/^/    /' >&2
      reward=0
    fi
  else
    echo "FAIL: the upstream regression test did not pass against the repaired tree" >&2
    tail -40 /tmp/golden.out | sed 's/^/    /' >&2
    reward=0
  fi
fi

# ---------- 3. the project's own suite (data-free subset) ---------------------
echo "== project's own stemmer suite (data-free subset) =="
if ( cd /tmp && PYTHONPATH=/app/src:"$SP" python3 -S -m pytest -q -p no:cacheprovider \
     "$SRC/nltk/test/unit/test_stem.py::SnowballTest::test_russian" \
     "$SRC/nltk/test/unit/test_stem.py::SnowballTest::test_spanish" \
     "$SRC/nltk/test/unit/test_stem.py::SnowballTest::test_short_strings_bug" \
     "$SRC/nltk/test/unit/test_stem.py::PorterTest::test_lowercase_option" \
     "$SRC/nltk/test/unit/test_stem.py::PorterTest::test_oed_bug" \
  ) > /tmp/stemkeel.out 2>&1; then
  echo "ok: the project's own stemmer tests all pass (nothing else broke)"
else
  echo "FAIL: a project stemmer test that passed at the parent now fails" >&2
  tail -30 /tmp/stemkeel.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 4. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
rm -rf /tmp/verify && mkdir -p /tmp/verify
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  if ! cp "$case"/*_test.py /tmp/verify/ 2>/dev/null; then
    echo "FAIL: could not stage hidden case $(basename "$case")" >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2
  reward=0
fi
if ( cd /tmp/verify && PYTHONPATH=/app/src:"$SP" python3 -S -m pytest -q -p no:cacheprovider zz_hidden_*_test.py ) \
   > /tmp/hidden.out 2>&1; then
  np=$(grep -cE "^[0-9]+ passed" /tmp/hidden.out || true)
  echo "ok: all hidden cases passed across $n_hidden case dirs"
else
  echo "FAIL: one or more hidden cases failed" >&2
  tail -60 /tmp/hidden.out | sed 's/^/    /' >&2
  reward=0
fi

# ---------- 5. the agent's own reproduction, both directions ------------------
echo "== reproduction deliverable =="
if [ ! -f "$REPRO" ]; then
  echo "FAIL: deliverable /app/reproduce.py does not exist" >&2
  reward=0
else
  if ! grep -q "SnowballStemmer" "$REPRO" 2>/dev/null; then
    echo "FAIL: /app/reproduce.py does not use NLTK's Snowball stemmer at all" >&2
    reward=0
  fi

  # 5a. against the PRISTINE PARENT tree (staged copy with the parent bytes
  #     of snowball.py), the reproduction MUST fail: it is a genuine repro.
  echo "== reproduction vs pre-fix (pristine parent) tree =="
  rm -rf /tmp/prefix-nltk && mkdir -p /tmp/prefix-nltk
  cp -a "$SRC/nltk" /tmp/prefix-nltk/nltk
  git -C "$SRC" show HEAD:nltk/stem/snowball.py > /tmp/prefix-nltk/nltk/stem/snowball.py
  ( cd /tmp && PYTHONPATH=/tmp/prefix-nltk:"$SP" timeout 90 python3 -S "$REPRO" ) \
     > /tmp/repro-prefix.log 2>&1
  prc=$?
  if [ "$prc" -ne 0 ]; then
    echo "ok: reproduction failed on the pre-fix tree (exit $prc)"
  else
    echo "FAIL: the reproduction exited 0 on a pristine PARENT tree -- it does not actually reproduce the bug" >&2
    tail -20 /tmp/repro-prefix.log | sed 's/^/    /' >&2
    reward=0
  fi

  # 5b. A/B control: the SAME staging mechanism but with the repaired tree's
  #     own bytes must make the reproduction pass. Together with 5a this proves
  #     the script discriminates the buggy tree from the fixed one instead
  #     of failing whenever it is pointed at a staging directory.
  echo "== reproduction vs staged fixed (repaired) tree =="
  rm -rf /tmp/prefix-nltk && mkdir -p /tmp/prefix-nltk
  cp -a "$SRC/nltk" /tmp/prefix-nltk/nltk
  ( cd /tmp && PYTHONPATH=/tmp/prefix-nltk:"$SP" timeout 90 python3 -S "$REPRO" ) \
     > /tmp/repro-prefix-fixed.log 2>&1
  pfrc=$?
  if [ "$pfrc" = 0 ] && grep -qF "$MARKER" /tmp/repro-prefix-fixed.log; then
    echo "ok: same staging, repaired bytes: reproduction prints the marker"
  else
    echo "FAIL: with the repaired bytes staged in the same way the reproduction did not pass (exit $pfrc) -- it is not a faithful A/B reproduction" >&2
    tail -20 /tmp/repro-prefix-fixed.log | sed 's/^/    /' >&2
    reward=0
  fi

  # 5c. against the repaired tree, the reproduction must pass with the marker.
  echo "== reproduction vs repaired tree =="
  ( cd /tmp && PYTHONPATH=/app/src:"$SP" timeout 90 python3 -S "$REPRO" ) > /tmp/repro-fixed.log 2>&1
  frc=$?
  if [ "$frc" = 0 ] && grep -qF "$MARKER" /tmp/repro-fixed.log; then
    echo "ok: reproduction passes against the repaired tree and prints the marker"
  else
    echo "FAIL: reproduction did not pass on the repaired tree (exit $frc)" >&2
    tail -30 /tmp/repro-fixed.log | sed 's/^/    /' >&2
    reward=0
  fi

  # 5d. the reproduction must resolve the LITERAL tree package for the
  #     repaired-tree run (the -S runs above already guarantee this; this is
  #     an explicit belt for the record).
  if ( cd /tmp && PYTHONPATH=/app/src:"$SP" python3 -S -c "import nltk.stem.snowball as m; import pathlib; assert str(pathlib.Path(m.__file__).resolve()).startswith('/app/src'), m.__file__" ) \
     > /tmp/repro-resolve.log 2>&1; then
    :
  else
    echo "note: nltk.stem.snowball does not resolve under /app/src from /tmp" >&2
  fi
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0