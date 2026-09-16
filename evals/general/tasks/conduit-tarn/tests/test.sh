#!/usr/bin/env bash
# Verifier for conduit-tarn.
#
# Grades the repository deliverable /app/conduit on five properties:
#   1. history integrity - every shipped commit (its initial HEAD) is still
#      reachable from a ref (no rebase/amend/reset of the shipped history);
#   2. a genuinely NEW test file exists under tests/ (vs the shipped tree) and
#      no shipped test file was deleted;
#   3. the full current test suite is green;
#   4. the same test suite, run against the shipped (pre-fix) code with the
#      current tests overlaid, is NOT green - i.e. the new/changed tests carry
#      real regression coverage that bites the pre-fix code;
#   5. the fixed tool produces the documented canonical document for three
#      hidden basket feeds (the affected input class).
set -u
mkdir -p /logs/verifier
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; [ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

REPO=/app/conduit

# ---- 1) repository and initial state -----------------------------------------
if [ ! -d "$REPO/.git" ]; then
  fail "/app/conduit is not a git repository"
  echo "VERDICT: 0 (repository missing)" >&2
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi

MANIFEST=/etc/conduit-initial.env
if [ ! -f "$MANIFEST" ]; then
  fail "initial-state manifest missing ($MANIFEST)"
else
  INITIAL_HEAD=$(grep -E '^INITIAL_HEAD=' "$MANIFEST" | head -1 | cut -d= -f2-)
fi

if [ -n "${INITIAL_HEAD:-}" ]; then
  if git -C "$REPO" cat-file -e "$INITIAL_HEAD^{commit}" 2>/dev/null; then
    :
  else
    fail "cannot read the shipped initial commit ($INITIAL_HEAD)"
  fi
  if git -C "$REPO" merge-base --is-ancestor "$INITIAL_HEAD" HEAD 2>/dev/null; then
    :
  else
    fail "history rewritten: shipped initial commit $INITIAL_HEAD is not an ancestor of HEAD (rebase/amend/reset/rewrite of the shipped history)"
  fi
fi

# ---- 2) materialise the shipped (pre-fix) tree for comparison -----------------
PREFIX=$WORK/prefix
mkdir -p "$PREFIX"
if ! git -C "$REPO" archive "$INITIAL_HEAD" 2>/dev/null | tar -x -C "$PREFIX"; then
  fail "could not materialise the shipped tree at $INITIAL_HEAD"
fi

# no shipped test deleted
( cd "$PREFIX/tests" 2>/dev/null && find . -name 'test_*.py' | sort ) > "$WORK/shipped_tests.txt" 2>/dev/null || true
( cd "$REPO/tests" 2>/dev/null && find . -name 'test_*.py' | sort ) > "$WORK/current_tests.txt" 2>/dev/null || true
if [ -s "$WORK/shipped_tests.txt" ]; then
  deleted=$(comm -23 "$WORK/shipped_tests.txt" "$WORK/current_tests.txt")
  if [ -n "$deleted" ]; then
    echo "   removed test files:"; echo "$deleted" | sed 's/^/     /' >&2
    fail "existing test file(s) removed or renamed"
  fi
  newtests=$(comm -13 "$WORK/shipped_tests.txt" "$WORK/current_tests.txt")
  if [ -z "$newtests" ]; then
    fail "no new test file added (a regression test must be a file that did not exist in the shipped tree)"
  else
    echo "   new test file(s): $newtests"
  fi
else
  fail "shipped tree has no tests/ directory"
fi

# ---- 3) full current suite must be green --------------------------------------
CUR_LOG=$WORK/current_pytest.log
( cd "$REPO" && python3 -m pytest -q -p no:cacheprovider tests/ ) >"$CUR_LOG" 2>&1
cur_rc=$?
if [ "$cur_rc" -ne 0 ]; then
  tail -30 "$CUR_LOG" | sed 's/^/   | /' >&2
  fail "current test suite is not green (pytest exit $cur_rc)"
fi

# ---- 4) the same tests must NOT be green against the shipped code -------------
# Overlay every current file except the package itself (conduit/) on the
# shipped tree, so the pre-fix run sees pre-fix code with the agent's tests.
for item in "$REPO"/* "$REPO"/.[!.]*; do
  [ -e "$item" ] || continue
  b=$(basename "$item")
  case "$b" in conduit|.git) continue ;; esac
  rm -rf "$PREFIX/$b"
  cp -r "$item" "$PREFIX/$b"
done
PRE_LOG=$WORK/prefix_pytest.log
( cd "$PREFIX" && python3 -m pytest -q -p no:cacheprovider tests/ ) >"$PRE_LOG" 2>&1
pre_rc=$?
if [ "$pre_rc" -eq 0 ]; then
  tail -5 "$PRE_LOG" | sed 's/^/   | /' >&2
  fail "pre-fix run is also green: the new regression test does not fail on the shipped code"
else
  echo "   pre-fix run fails as expected (pytest exit $pre_rc):"
  grep -E '^(FAILED|ERROR)' "$PRE_LOG" | head -10 | sed 's/^/     /' >&2 || true
fi

# ---- 5) hidden feeds in the affected class -------------------------------------
for case in H1 H2 H3; do
  feed=/tests/hidden/$case/feed.csv
  expected=/tests/hidden/$case/expected.json
  out=$WORK/out_$case.json
  if [ ! -f "$feed" ] || [ ! -f "$expected" ]; then
    fail "hidden case $case is incomplete"
    continue
  fi
  ( cd "$REPO" && timeout 120 python3 -m conduit "$feed" "$out" ) >/dev/null 2>&1
  hrc=$?
  if [ "$hrc" -ne 0 ] || [ ! -s "$out" ]; then
    fail "hidden case $case: tool did not produce an output document (exit $hrc)"
    continue
  fi
  if ! python3 - "$out" "$expected" "$case" <<'PY'
import json
import sys

got_path, want_path, case = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(got_path) as fh:
        got = json.load(fh)
    with open(want_path) as fh:
        want = json.load(fh)
except Exception as exc:
    print("   hidden case %s: cannot parse outputs: %s" % (case, exc),
          file=sys.stderr)
    sys.exit(1)
if got != want:
    print("   hidden case %s: canonical document differs from expected"
          % case, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
  then
    fail "hidden case $case: output does not match the documented canonical document"
  else
    echo "   hidden case $case: ok"
  fi
done

# ---- verdict -------------------------------------------------------------------
if [ "$FAILED" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
  echo 1 > /logs/verifier/reward.txt
else
  echo "VERDICT: 0 (failures present)" >&2
  echo 0 > /logs/verifier/reward.txt
fi
exit 0