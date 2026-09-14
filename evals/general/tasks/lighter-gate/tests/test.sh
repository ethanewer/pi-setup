#!/bin/bash
# lighter-gate verifier.
#
# The agent must have (1) written a pytest reproduction at
# /app/repro/test_no_args_is_help.py that captures the no-args-help exit-status
# bug, and (2) fixed the click library in /app/src so that reproduction passes.
# We verify five independent things:
#   1. the reproduction FAILS against a pristine pre-fix snapshot
#      (/opt/pristine, extracted at build time, agent-writable? no: root-owned
#      and not in the a+rwX set) - a repro that cannot see the bug is vacuous;
#   2. the reproduction PASSES against the repaired tree;
#   3. the golden tests extracted from the upstream fix commit (/opt/golden,
#      never committed to this task) pass when overlaid onto /app/src/tests;
#   4. a 10-file slice of the project's own suite (422 tests) still passes;
#   5. three hidden cases exercising the same code path from inputs the
#      upstream tests do not use all pass against the repaired tree.
# Every python invocation runs isolated (python3 -I: no user site, no cwd on
# sys.path, no PYTHONPATH) except the pristine direction (python3 -P with an
# explicit PYTHONPATH), so no agent-authored file from a writable directory can
# hook the interpreter. The suite runs from /app/src because one upstream test
# (test_expand_args) globs against the cwd. pytest runs additionally confine
# conftest loading to /app/src/tests. Any failure -> reward 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
cd /

UPSTREAM_SHA=4271fe283dc9365563aebb369ada8d20eee015a8
FIX_SHA=d8763b93021c416549b5f8b4b5497234619410db
REPRO=/app/repro/test_no_args_is_help.py
PRIST=/opt/pristine
GOLD=/opt/golden
SRC=/app/src
SUITE="test_basic.py test_chain.py test_options.py test_arguments.py test_types.py test_defaults.py test_parser.py test_utils.py test_formatting.py test_context.py"

ok=1
fail() { echo "lighter-gate FAIL: $1" >&2; ok=0; }

# --- 0. static identity of the image the trial ran in ------------------------
[ -d "$SRC" ] || fail "no checkout at $SRC"
[ -d "$PRIST" ] || fail "no pristine snapshot at $PRIST"
[ -f "$GOLD/test_commands.py" ] && [ -f "$GOLD/conftest.py" ] || fail "no golden extraction at $GOLD"
( cd "$SRC" && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" ) \
  || fail "checkout HEAD is not the pinned parent $UPSTREAM_SHA"
( cd "$SRC" && ! git cat-file -e "$FIX_SHA^{commit}" 2>/dev/null ) \
  || fail "fix commit IS reachable inside the shipped clone"
( cd "$SRC" && test "$(git log --all --oneline | wc -l)" = "1" ) \
  || fail "shipped clone holds more than the pinned parent commit (a newer main tip would leak the fixed code)"
PYTHONPATH="$PRIST/src" python3 -P -c "import click; assert click.__file__.startswith('$PRIST'), click.__file__" \
  || fail "pristine snapshot does not import independently"
python3 -I -c "import click; assert click.__file__.startswith('$SRC/src/click'), click.__file__" \
  || fail "editable install does not resolve to the checkout"

# --- 1. the declared deliverable exists --------------------------------------
[ -f "$REPRO" ] || fail "missing deliverable $REPRO"

# --- 2. the reproduction must FAIL against the pristine pre-fix tree ---------
PYTHONPATH="$PRIST/src" python3 -P -m pytest -q -p no:cacheprovider "$REPRO" >/tmp/lg-prist.log 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  tail -5 /tmp/lg-prist.log >&2
  fail "reproduction passed against the PRE-FIX code, so it does not capture the bug"
fi

# --- 3. the reproduction must PASS against the repaired tree -----------------
python3 -I -m pytest -q -p no:cacheprovider "$REPRO" >/tmp/lg-repro.log 2>&1 \
  || { tail -5 /tmp/lg-repro.log >&2; fail "reproduction did not pass against your repaired tree"; }

# --- 4. golden tests from the fix commit, overlaid on the agent's tree -------
cp -f "$GOLD/test_commands.py" "$GOLD/conftest.py" "$SRC/tests/"
(cd "$SRC" && python3 -I -m pytest -q -p no:cacheprovider --confcutdir="$SRC/tests" \
    "tests/test_commands.py::test_command_no_args_is_help" \
    "tests/test_commands.py::test_group_with_args") >/tmp/lg-golden.log 2>&1 \
  || { tail -8 /tmp/lg-golden.log >&2; fail "upstream golden no-args-help tests failed"; }
(cd "$SRC" && python3 -I -m pytest -q -p no:cacheprovider --confcutdir="$SRC/tests" \
    "tests/test_commands.py") >/tmp/lg-golden-all.log 2>&1 \
  || { tail -8 /tmp/lg-golden-all.log >&2; fail "overlaid test_commands.py is not fully green"; }

# --- 5. the project's own suite must still pass (fix broke nothing) ----------
(cd "$SRC" && python3 -I -m pytest -q -p no:cacheprovider -o filterwarnings= --confcutdir="$SRC/tests" \
    $(for f in $SUITE; do printf 'tests/%s ' "$f"; done)) >/tmp/lg-suite.log 2>&1 \
  || { tail -8 /tmp/lg-suite.log >&2; fail "upstream suite subset failed after the fix"; }

# --- 6. hidden cases, against the repaired tree ------------------------------
for c in h1 h2 h3; do
  python3 -I "/tests/hidden/$c/check.py" >/tmp/lg-h-$c.log 2>&1 \
    || { cat /tmp/lg-h-$c.log >&2; fail "hidden case $c failed"; }
done

reward=0
[ "$ok" -eq 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "lighter-gate reward=$reward" >&2
exit 0