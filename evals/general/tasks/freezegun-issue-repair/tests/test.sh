#!/bin/sh
set -u
mkdir -p /logs/verifier
failures=0
printf '0\n' > /logs/verifier/reward.txt
trap 'if [ "$failures" -ne 0 ]; then printf "0\n" > /logs/verifier/reward.txt; fi' EXIT
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

[ -f /app/freezegun_base/freezegun/api.py ] || fail "api.py missing"
[ -f /app/reproduce.py ] || fail "reproduce.py missing"

if [ -f /tests/fixtures/base_manifest.sha256 ] && [ -d /tests/fixtures/freezegun_pristine ]; then
    [ "$(cat /tests/fixtures/base_commit.txt 2>/dev/null)" = "c9bf52c5aa12ea1b5b8647a136a92504ea071f2f" ] \
        || fail "trusted fixture base commit marker is incorrect"
    if ! (cd /tests/fixtures/freezegun_pristine && sha256sum -c ../base_manifest.sha256 >/dev/null 2>&1); then
        fail "trusted pristine fixture does not match base snapshot"
    fi
else
    fail "trusted pristine fixture missing"
fi

if [ -f /app/reproduce.py ]; then
    out=$(python3 /app/reproduce.py 2>&1); rc=$?
    [ "$rc" -eq 0 ] || fail "reproduction failed on repaired source: $out"
    [ "$out" = 'BUILT PASS
CALLS 2' ] || fail "repaired reproduction output contract mismatch: $out"

    pristine=$(FREEZEGUN_SOURCE=/tests/fixtures/freezegun_pristine python3 /app/reproduce.py 2>&1); oldrc=$?
    [ "$oldrc" -ne 0 ] || fail "reproduction passed on pristine source"
    if ! python3 - "$pristine" <<'PY'
import re
import sys

lines = sys.argv[1].splitlines()
if len(lines) != 2 or lines[0] != "BUILT FAIL" or not re.fullmatch(r"CALLS [0-9]+", lines[1]):
    raise SystemExit(1)
PY
    then
        fail "pristine reproduction output contract mismatch: $pristine"
    fi
fi

for d in /tests/hidden/*/; do
    [ -f "$d/run.py" ] || continue
    if ! python3 "$d/run.py"; then fail "hidden case $(basename "$d") failed after repair"; fi
    if [ "$(basename "$d")" = "as_arg" ]; then
        if FREEZEGUN_SOURCE=/tests/fixtures/freezegun_pristine python3 "$d/run.py" >/dev/null 2>&1; then
            fail "as_arg hidden case passed on pristine source"
        fi
    fi
done

if python3 - <<'PY'
import sys
sys.path.insert(0, '/app/freezegun_base')
from freezegun import freeze_time
try:
    @freeze_time('2022-01-01', as_arg=True, as_kwarg='x')
    def f(factory, *, x): pass
    f()
except AssertionError:
    pass
else:
    raise SystemExit(1)
PY
then :; else fail "both injection modes no longer rejected"; fi

if [ "$failures" -eq 0 ]; then
    echo 1 > /logs/verifier/reward.txt
    echo 'REWARD 1'
else
    echo 0 > /logs/verifier/reward.txt
    echo "REWARD 0 ($failures failures)"
fi
exit 0
