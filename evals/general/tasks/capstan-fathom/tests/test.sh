#!/bin/bash
# Verifier for capstan-fathom: an upstream-clone debugging task on flake8.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# on Python 3.10+ flake8 crashes with
#   AttributeError: 'int' object has no attribute 'rstrip'
# instead of emitting its syntax-error report, because the code that recovers
# the report position from a SyntaxError assumes the pre-3.10 four-element
# detail tuple, reads the tuple's last element (now an integer end-offset) as
# the physical line of source, and calls string methods on it.
#
# The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit and is
#      the only commit; the upstream fix commit is not reachable; the
#      regression-test file is byte-identical to the upstream test extracted
#      into /opt/golden; src/flake8/checker.py holds a non-empty diff; and
#      nothing else in the repository changed);
#   1. runs the project's own regression test
#      (test_handling_syntaxerrors_across_pythons) with the project's own
#      runner against the repaired tree and requires it to pass, then runs a
#      slice of the project's own existing suite (tests/integration/
#      test_checker.py plus five unit files, 135 tests) and requires it fully
#      green, proving the fix broke nothing else;
#   2. runs four authored hidden cases that exercise the same position-
#      recovery code from inputs the upstream test does not use: real parse
#      failures of multi-line modules, six-element tuples whose source text
#      is unavailable or whose end-fields point elsewhere, the legacy
#      four-element tuple layout, and the tokenisation-error/fallback paths.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
# Never trust a reward file that predates this run (a pre-written file would
# short-circuit the EXIT trap on a crashed run).
rm -f /logs/verifier/reward.txt
reward=1

# The verifier disables site processing (-S) so no .pth file, user-site hook
# or sitecustomize the agent may have planted can intercept the code under
# test: the burden of the fix must sit in the /app/src tree itself. Imports
# still resolve because the real site-packages is put back on PYTHONPATH.
PY_SITE=$(python3 -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null || true)
if [ -z "$PY_SITE" ] || [ ! -d "$PY_SITE" ]; then
  PY_SITE=/usr/local/lib/python3.12/site-packages
fi
export PY_SITE

SRC=/app/src
PARENT_SHA=d25cc10e382bcbd59cea47e0172f1e35cd3ee90d
FIX_SHA=85c2be3b5291a73a2e737219c040019c14cf3eee
GOLDEN=/opt/golden/test_checker.py
GOLDEN_SHA=cbace8aece29be37ebc68b91ff46ded4ae9f0583ac0b7c7b9d90130b2771d844

dotests() {  # dotests <file...> : run pytest with site processing disabled
  ( cd /app/src && PYTHONPATH=/app/src/src:$PY_SITE python3 -S -m pytest "$@" \
      -q -W ignore::DeprecationWarning -p no:cacheprovider )
}

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0. tree provenance ------------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if [ "$(git -C "$SRC" rev-list --count HEAD 2>/dev/null)" != "1" ]; then
  fail "/app/src has more than the single pinned commit"
else
  echo "ok: the clone contains exactly one commit"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

if [ -z "$(git -C "$SRC" diff -- src/flake8/checker.py 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: src/flake8/checker.py differs from the pinned commit"
fi

tree_golden=$(sha256sum < "$SRC/tests/integration/test_checker.py" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_golden" = "$GOLDEN_SHA" ]; then
  echo "ok: tests/integration/test_checker.py is byte-identical to the upstream regression test"
else
  fail "tests/integration/test_checker.py was altered (${tree_golden:-missing})"
fi
if [ -f "$GOLDEN" ] && [ "$(sha256sum < "$GOLDEN" | cut -d' ' -f1)" = "$GOLDEN_SHA" ]; then
  echo "ok: /opt/golden/test_checker.py intact"
else
  fail "/opt/golden/test_checker.py missing or altered"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
expected=" M src/flake8/checker.py"$'\n'" M tests/integration/test_checker.py"
if [ "$porcelain" = "$expected" ]; then
  echo "ok: working tree differs from the pinned commit only in the fix and the shipped regression test"
else
  fail "unexpected working-tree changes:"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

# ---------- 1. the project's own regression test + suite slice ----------------
echo "== upstream regression test =="
golden_out=$(dotests tests/integration/test_checker.py \
    -k test_handling_syntaxerrors_across_pythons 2>&1)
grc=$?
echo "$golden_out" | tail -3 | sed 's/^/    /'
if [ "$grc" != 0 ] || ! echo "$golden_out" | grep -q "1 passed"; then
  fail "the upstream regression test test_handling_syntaxerrors_across_pythons does not pass against the repaired tree"
else
  echo "ok: upstream regression test passes"
fi

echo "== project's own suite slice (135 tests) =="
suite_out=$(dotests tests/integration/test_checker.py \
    tests/unit/test_checker_manager.py tests/unit/test_file_checker.py \
    tests/unit/test_statistics.py tests/unit/test_utils.py \
    tests/unit/test_violation.py 2>&1)
src_rc=$?
echo "$suite_out" | tail -3 | sed 's/^/    /'
if [ "$src_rc" != 0 ] || ! echo "$suite_out" | grep -q "135 passed"; then
  fail "the project's own suite slice is not fully green (expected: 135 passed)"
else
  echo "ok: suite slice green: 135 passed"
fi

# ---------- 2. authored hidden cases ------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  for f in "$case"check.py; do
    [ -f "$f" ] || continue
    n_hidden=$((n_hidden + 1))
    cname=$(basename "$case")
    out=$(PYTHONPATH=$PY_SITE:/app/src/src python3 -S "$f" 2>&1)
    rc=$?
    if [ "$rc" = 0 ]; then
      echo "ok: hidden case $cname"
      echo "$out" | sed 's/^/    /'
    else
      fail "hidden case $cname"
      echo "$out" | tail -6 | sed 's/^/    /' >&2
    fi
  done
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0