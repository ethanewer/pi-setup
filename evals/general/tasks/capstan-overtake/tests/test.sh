#!/bin/bash
# Verifier for capstan-overtake: an upstream-clone debugging task on spaCy.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# displacy.render(..., jupyter=True) crashes with
# "ImportError: cannot import name 'display' from 'IPython.core.display'"
# because the renderer imports the IPython display helper from the deprecated
# IPython.core.display module path that IPython>=9 removed.
#
# The verifier:
#   0. asserts the environment is intact (IPython is still 9.x, the sole
#      dependency that makes the parent fail) and tree provenance (HEAD is
#      still the pinned parent commit, the upstream fix commit is NOT
#      reachable from the clone, the working tree differs ONLY in
#      spacy/displacy/__init__.py);
#   1. runs the authored golden regression test (/opt/golden/..., mirrors the
#      upstream reproduction; the upstream fix commit contained no test);
#   2. runs three authored hidden cases exercising the same jupyter display
#      branch from inputs the golden test does not use (style="dep" on an
#      annotated Doc, style="span" on a spans-annotated Doc, style="ent" with
#      manual=True dict input and a custom colour palette); each asserts via
#      a display spy that the rendered markup is actually handed to IPython;
#   3. runs the project's own existing displaCy test module
#      (spacy/tests/test_displacy.py) to prove nothing else broke.
#
#   Additionally, step 1b runs a wrapper-free probe: the reproduction is
#   re-executed under ``python3 -S`` (no site processing), so an agent that
#   satisfied the pytest steps by installing a shim in site-packages (e.g. a
#   sitecustomize.py or .pth that re-exports ``display`` from
#   IPython.core.display) instead of fixing the checkout is caught: the buggy
#   import still raises, and reward stays 0. A tree that genuinely fixes the
#   import passes the probe.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=f5d04868e1e66d0acd6417b1c8099bcd4068fff7
FIX_SHA=94d6be8a9b1dbecc92820bd7996cd8c75e186320
GOLDEN=/opt/golden/test_displacy_jupyter.py

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0. environment sanity ----------------------------------------------
echo "== environment sanity =="
if python3 -c 'import IPython, sys; sys.exit(0 if IPython.__version__.startswith("9.") else 1)' 2>/tmp/ipy.err; then
  echo "ok: IPython is 9.x (the bug-triggering release line)"
else
  fail "IPython is not 9.x; the bug-triggering dependency was replaced"
  cat /tmp/ipy.err >&2
fi

# ---------- 1. tree provenance --------------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is the pinned parent commit"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

if git -C "$SRC" diff --quiet -- spacy/displacy/__init__.py 2>/dev/null; then
  fail "spacy/displacy/__init__.py is unchanged (no fix was implemented)"
else
  echo "ok: spacy/displacy/__init__.py was modified"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
n_lines=$(printf '%s\n' "$porcelain" | grep -cv '^[[:space:]]*$')
if [ "$n_lines" = 1 ] && printf '%s\n' "$porcelain" | grep -q 'spacy/displacy/__init__.py'; then
  echo "ok: working tree differs from the pinned commit only in the fixed file"
else
  fail "unexpected working-tree changes:"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

# ---------- 1b. wrapper-free tree-level fix -----------------------------------
# The pytest steps above can be satisfied by a shim installed in site-packages
# that re-imports the removed name, with the tree left unfixed. Re-run the
# reproduction under python3 -S where sitecustomize/.pth never load, so only a
# fix that actually lives in the checkout can pass.
echo "== wrapper-free tree-level fix =="
if python3 -S /tests/probe_jupyter_no_wrapper.py "$SRC" > /tmp/probe.log 2>&1; then
  echo "ok: jupyter render works with site processing disabled (the fix is in the tree)"
else
  fail "jupyter render still raises without site processing (a wrapper masking an unfixed tree does not count as a fix)"
  tail -8 /tmp/probe.log | sed 's/^/    /' >&2
fi

# ---------- 2. golden regression test (authored from the reproduction) ----------
echo "== golden regression test =="
if [ ! -f "$GOLDEN" ]; then
  fail "/opt/golden/test_displacy_jupyter.py is missing from the image"
else
  if python3 -m pytest -q -p no:cacheprovider "$GOLDEN" > /tmp/golden.log 2>&1; then
    echo "ok: golden regression test passed"
  else
    fail "golden regression test failed"
    tail -40 /tmp/golden.log | sed 's/^/    /' >&2
  fi
fi

# ---------- 3. authored hidden cases --------------------------------------------
echo "== hidden cases =="
n_hidden=0
case_dirs=""
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  case_dirs="$case_dirs $case"
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were shipped"
fi
if python3 -m pytest -q -p no:cacheprovider $case_dirs > /tmp/hidden.log 2>&1; then
  echo "ok: $n_hidden hidden case(s) passed"
else
  fail "authored hidden cases failed"
  tail -40 /tmp/hidden.log | sed 's/^/    /' >&2
fi

# ---------- 4. the project's own existing displaCy suite ------------------------
echo "== the project's own displaCy test module =="
if ( cd "$SRC" && python3 -m pytest -q -p no:cacheprovider spacy/tests/test_displacy.py ) > /tmp/suite.log 2>&1; then
  echo "ok: spacy/tests/test_displacy.py passed"
else
  fail "spacy/tests/test_displacy.py is not fully green"
  tail -30 /tmp/suite.log | sed 's/^/    /' >&2
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0