#!/bin/bash
# Verifier for crance-bell: an upstream-clone debugging task on scipy/scipy.
#
# The agent must, in the real checkout at /app/src, (a) discover that
# stats.wilcoxon(x, method='exact') reports a p-value of exactly 0.0 for
# strongly one-sided samples even though the true probability is tiny but
# nonzero, (b) write its own failing reproduction /app/reproduce.py, and
# (c) fix the bug in the library source. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      object store holds exactly that one commit, the upstream fix commit is
#      not reachable, no tracked file was deleted, no file was added, no test
#      file and no file outside scipy/ was modified, and the library imports
#      resolve to the checked-out tree);
#   1. requires /app/reproduce.py and runs it (it must PASS on the repaired
#      tree), then reverts EVERY modified tracked file to the parent blobs
#      and proves the reproduction FAILS on the pre-fix tree, then restores
#      the agent's work and re-proves the reproduction passes;
#   2. runs the project's own regression test for this exact bug, shipped in
#      tests/golden/ and mounted at /tests only for the verifier phase (a
#      pinned sha256 detects tampering);
#   3. runs five authored hidden cases exercising the same code path from
#      inputs the upstream regression test does not use (sample sizes 60, 70,
#      80, 90 and a tied sample);
#   4. runs the project's own existing TestWilcoxon suite from the tree,
#      proving the fix broke nothing else.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

SRC=/app/src
PARENT=d9b45feb89659479d666e1818bc1aa556292659e
FIX=6dbd21acb0ab2ad22a06b6351f83a47743d8b0b5
GOLDEN_SHA=370553ee4b28f7bf9d8e30b21f0af0572cac9f03b651eb4247be00faa2cf5e01

export PYTHONDONTWRITEBYTECODE=1 PYTHONNOUSERSITE=1
unset PYTHONPATH

fail() {
    echo "FAIL: $1"
    mkdir -p /logs/verifier
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

cd "$SRC" || fail "/app/src is missing"

# ---------- 0. tree provenance ----------------------------------------------
echo "== tree provenance =="
[ "$(git rev-parse HEAD 2>/dev/null)" = "$PARENT" ] \
    || fail "HEAD is $(git rev-parse HEAD 2>/dev/null), expected pinned parent $PARENT"
echo "ok: HEAD is the pinned parent commit"

ncommits=$(git rev-list --all --count 2>/dev/null || echo -)
[ "$ncommits" = "1" ] \
    || fail "clone contains $ncommits commits; it must contain exactly the pinned parent commit"
echo "ok: exactly one commit object reachable"

if git cat-file -e "${FIX}^{commit}" 2>/dev/null; then
    fail "the upstream fix commit is reachable from /app/src's object store (the answer was fetched, not implemented)"
fi
echo "ok: upstream fix commit not present in the working clone"

unreach=$(git fsck --no-reflogs --unreachable 2>/dev/null | wc -l)
[ "$unreach" = "0" ] \
    || fail "object store contains $unreach unreachable objects (hidden history was fetched)"
echo "ok: object store holds nothing beyond the pinned commit"

# Working-tree scope: at least one tracked file under scipy/ (outside any
# tests/ tree) modified, nothing added, nothing deleted, no test file and no
# file outside scipy/ touched.
checked=0
saw_mod=0
bad_tree=0
while IFS= read -r line; do
    [ -z "$line" ] && continue
    x=${line:0:1}; y=${line:1:1}; path=${line:3}
    case "$x$y" in
        \?\?)
            echo "FAIL: untracked file in the working tree: $path" >&2; bad_tree=1 ;;
        *D*)
            echo "FAIL: a tracked file was deleted: $path" >&2; bad_tree=1 ;;
        A*)
            echo "FAIL: a new file was added to the working tree: $path" >&2; bad_tree=1 ;;
        *M*)
            case "$path" in
                scipy/stats/tests/*|*/tests/*)
                    echo "FAIL: a tracked test file was modified: $path" >&2; bad_tree=1 ;;
                scipy/*)
                    saw_mod=1; checked=$((checked+1)) ;;
                *)
                    echo "FAIL: a tracked file outside scipy/ was modified: $path" >&2; bad_tree=1 ;;
            esac
            ;;
        *)
            echo "FAIL: unexpected working-tree change: $line" >&2; bad_tree=1 ;;
    esac
done <<< "$(git status --porcelain 2>/dev/null || true)"
[ "$bad_tree" = 0 ] || fail "working tree has forbidden changes (above)"
[ "$saw_mod" = 1 ] || fail "no library source file under scipy/ was modified: the bug is still present in the tree"
echo "ok: $checked tracked file(s) under scipy/ modified, nothing else touched"

# The deliverables must resolve to the checked-out tree, and the live
# implementation of the exact-Wilcoxon survival function must be the tree's
# own source (a wrapper planted in site-packages or user site would leave the
# buggy tree intact while only the wrapper's behaviour changes).
if ! ( cd / && python3 -c "
import inspect, sys
import scipy
from scipy.stats._wilcoxon import WilcoxonDistribution
sf = inspect.getsourcefile(WilcoxonDistribution.sf)
assert scipy.__file__.startswith('$SRC/'), scipy.__file__
assert sf.startswith('$SRC/'), sf
print('imports resolve to the checked-out tree:', sf)
" > /tmp/import_probe.log 2>&1 ); then
    tail -5 /tmp/import_probe.log | sed 's/^/    /' >&2
    fail "library does not resolve to the checked-out tree at /app/src"
fi
echo "ok: scipy imports resolve to $SRC"

# ---------- 1. the agent's own reproduction, both directions -----------------
echo "== the agent's own reproduction =="
[ -s /app/reproduce.py ] || fail "/app/reproduce.py is missing or empty"

if ! ( cd / && python3 /app/reproduce.py > /tmp/repro_fixed.log 2>&1 ); then
    tail -20 /tmp/repro_fixed.log | sed 's/^/    /' >&2
    fail "the reproduction fails on the agent-repaired tree (no fix implemented)"
fi
echo "ok: the reproduction passes on the repaired tree"

# Now prove the reproduction genuinely demonstrates the PARENT bug: revert
# every modified tracked file to its parent blob, run the reproduction (it
# MUST fail), then restore the agent's work and re-run (it MUST pass again).
mods=$(git diff --name-only HEAD 2>/dev/null || true)
backup=/tmp/agent_fix_backup
rm -rf "$backup"; mkdir -p "$backup"
for path in $mods; do
    mkdir -p "$backup/$(dirname "$path")"
    cp "$path" "$backup/$path"
    git show "$PARENT:$path" > "$path" 2>/dev/null || true
done
if ( cd / && python3 /app/reproduce.py > /tmp/repro_parent.log 2>&1 ); then
    for path in $mods; do cp "$backup/$path" "$path"; done
    tail -5 /tmp/repro_parent.log | sed 's/^/    /' >&2
    fail "the reproduction PASSES on the pre-fix (reverted) tree; it does not demonstrate the bug"
fi
echo "ok: the reproduction fails on the pre-fix tree (bug demonstrated)"
for path in $mods; do
    cp "$backup/$path" "$path"
done
if ! ( cd / && python3 /app/reproduce.py > /tmp/repro_restored.log 2>&1 ); then
    tail -20 /tmp/repro_restored.log | sed 's/^/    /' >&2
    fail "the reproduction no longer passes after restoring the agent's fix"
fi
echo "ok: the reproduction passes again once the fix is restored"
rm -rf "$backup"

# ---------- 2. golden: the upstream regression test for this bug -------------
# Shipped in the task tree at tests/golden/ and mounted at /tests only at
# verification time (the agent phase mounts neither /tests nor /solution),
# so the agent never sees the upstream reproduction or its exact reference.
# A pinned sha256 of the bytes detects tampering.
echo "== golden regression test (upstream test_gh26026) =="
[ -f /tests/golden/test_gh26026.py ] || fail "golden regression test not mounted at /tests/golden"
got=$(sha256sum /tests/golden/test_gh26026.py 2>/dev/null | cut -d' ' -f1)
[ "$got" = "$GOLDEN_SHA" ] \
    || fail "golden regression test missing or tampered with (sha256 $got)"
echo "ok: golden file integrity confirmed ($GOLDEN_SHA)"
if ! ( cd /tmp && python3 -m pytest -o addopts="" -p no:cacheprovider \
        /tests/golden/test_gh26026.py -v > /tmp/golden.log 2>&1 ); then
    tail -25 /tmp/golden.log | sed 's/^/    /' >&2
    fail "golden regression test failed"
fi
grep -q "test_exact_zero_pvalue_regression PASSED" /tmp/golden.log \
    || fail "golden test did not actually run and pass"
echo "ok: upstream regression test passes"

# ---------- 3. hidden cases --------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for testfile in /tests/hidden/*/test_*.py; do
    [ -e "$testfile" ] || continue
    n_hidden=$((n_hidden + 1))
    name=$(basename "$(dirname "$testfile")")
    if ! ( cd /tmp && python3 -m pytest -o addopts="" -p no:cacheprovider \
            "$testfile" -v > "/tmp/hidden_${name}.log" 2>&1 ); then
        tail -25 "/tmp/hidden_${name}.log" | sed 's/^/    /' >&2
        fail "hidden case $name failed"
    fi
    grep -q "PASSED" "/tmp/hidden_${name}.log" \
        || fail "hidden case $name did not actually run and pass"
    echo "ok: hidden case $name"
done
[ "$n_hidden" -ge 2 ] || fail "fewer than two hidden cases were exercised"

# ---------- 4. the project's own existing test suite -------------------------
echo "== the project's own existing suite (TestWilcoxon) =="
if ! ( cd "$SRC" && python3 -m pytest -o addopts="" -p no:cacheprovider \
        "scipy/stats/tests/test_morestats.py::TestWilcoxon" -q \
        > /tmp/ownsuite.log 2>&1 ); then
    tail -30 /tmp/ownsuite.log | sed 's/^/    /' >&2
    fail "the project's own TestWilcoxon suite failed"
fi
grep -q "passed" /tmp/ownsuite.log || fail "TestWilcoxon produced no passing run"
tail -2 /tmp/ownsuite.log | sed 's/^/    /'
echo "ok: the project's own TestWilcoxon suite passes"

echo "REWARD=1"
echo 1 > /logs/verifier/reward.txt
exit 0