#!/bin/bash
# Verifier for trawler-bowsprit: an upstream-clone debugging task on
# pypa/setuptools (issue #4302).
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# Distribution.get_fullname() embeds canonicalize_version(self.get_version())
# in release/archive names, so every trailing-zero-normalised version loses
# fidelity ("1.0" -> "1", "0.0.0" -> "0"). The agent must first write its own
# failing reproduction (/app/reproduce.py) and then fix the tree. The
# verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, the only tree change is the
#      production fix file, and the fix-era regression test the image
#      carries at /opt/golden is byte-identical to the upstream original);
#   1. runs the agent's own reproduction against a pristine worktree of the
#      parent commit (must fail, i.e. must genuinely reproduce the bug) and
#      against the repaired tree (must pass);
#   2. copies the repaired tree, overlays the fix-era golden regression test
#      (test_build_with_discovered_name) and requires the project's own
#      suite to pass end to end on the overlay: test_config_discovery.py,
#      test_sdist.py, test_egg_info.py, test_wheel.py — 223 collected at the
#      parent, all green once fixed (the golden node is part of that run);
#   3. runs three authored hidden cases exercising the same code path with
#      inputs the upstream test does not use: a pyproject-declared "1.0"
#      sdist, a release-name version matrix (0.0.0/1.0/2.3.0/1.0b1/
#      3.0.0rc1/2024.4.13), and a setup.cfg-declared "1.0.0" sdist.
#
# Cheats that were tried and rejected by this verifier (each verified to
# score 0): an always-passing reproduction (killed by the pristine-tree run
# in step 1), no fix at all (porcelain + step 1), a fix that only special-
# cases the default version (kernel of the matrix hidden case), modifying a
# different file (porcelain), tampering with /opt/golden (sha check), and
# moving HEAD (provenance check).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

echo "== environment (diagnostic) =="
echo "PYTEST_ADDOPTS=${PYTEST_ADDOPTS-}"
env | grep -iE "^PYTEST|^COVERAGE|^PYTHONPATH" | sed 's/^/    /' || true

SRC=/app/src
PARENT_SHA=92b45e9817ae829a5ca5a5962313a56b943cad91
FIX_SHA=df45427cbb67c1149fcf5d2d1e2705e69b3baf0c
GOLDEN=/opt/golden/test_config_discovery.py
GOLDEN_SHA=4e26abc25c27b75265f960aadc90cb9d2c20669f8378eafe56410544494c4678
REPRO=/app/reproduce.py
MODULES="setuptools/tests/test_config_discovery.py setuptools/tests/test_sdist.py setuptools/tests/test_egg_info.py setuptools/tests/test_wheel.py"

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
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

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
if [ "$porcelain" = " M setuptools/_core_metadata.py" ]; then
  echo "ok: working tree differs from the pinned commit only in the production fix"
elif [ -z "$porcelain" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  fail "unexpected working-tree changes (expected exactly ' M setuptools/_core_metadata.py'):"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

if [ ! -s "$REPRO" ]; then
  fail "the deliverable $REPRO is missing or empty"
else
  echo "ok: reproduce.py exists"
fi

golden_sha=$(sha256sum < "$GOLDEN" 2>/dev/null | cut -d' ' -f1)
if [ "$golden_sha" = "$GOLDEN_SHA" ]; then
  echo "ok: the fix-era golden regression test is byte-identical to upstream"
else
  fail "the golden regression test at /opt/golden was altered (${golden_sha:-missing})"
fi

# ---------- 1. the agent's own reproduction, both directions -----------------
echo "== reproduction against the pristine parent tree (must fail) =="
rm -rf /tmp/prefix
if git -C "$SRC" worktree add --detach /tmp/prefix HEAD > /tmp/worktree.log 2>&1; then
  echo "ok: pristine worktree created"
else
  fail "could not create the pristine worktree"
  tail -5 /tmp/worktree.log | sed 's/^/    /' >&2
fi
if [ "$reward" = 1 ]; then
  set +e
  ( cd /tmp && PYTHONPATH=/tmp/prefix PYTHONDONTWRITEBYTECODE=1 python3 "$REPRO" ) > /tmp/repro-pristine.log 2>&1
  rc_pristine=$?
  set -e
  if [ "$rc_pristine" -ne 0 ]; then
    echo "ok: reproduction fails on the pristine tree (exit $rc_pristine)"
    tail -6 /tmp/repro-pristine.log | sed 's/^/    /'
  else
    fail "reproduction exited 0 on the pristine tree; it does not reproduce the bug"
    tail -6 /tmp/repro-pristine.log | sed 's/^/    /' >&2
  fi
fi
git -C "$SRC" worktree remove --force /tmp/prefix > /dev/null 2>&1 || true

echo "== reproduction against the repaired tree (must pass) =="
if [ "$reward" = 1 ]; then
  set +e
  ( cd /tmp && python3 "$REPRO" ) > /tmp/repro-fixed.log 2>&1
  rc_fixed=$?
  set -e
  if [ "$rc_fixed" = 0 ]; then
    echo "ok: reproduction passes on the repaired tree"
    tail -3 /tmp/repro-fixed.log | sed 's/^/    /'
  else
    fail "reproduction failed on the repaired tree (exit $rc_fixed)"
    tail -12 /tmp/repro-fixed.log | sed 's/^/    /' >&2
  fi
fi

# ---------- 2. golden regression test + project suite on the repaired tree ---
echo "== overlay fix-era golden test and run the project's own suite =="
rm -rf /tmp/verify
if cp -a "$SRC" /tmp/verify 2>/dev/null && [ -f /tmp/verify/setuptools/_core_metadata.py ]; then
  :
else
  fail "could not copy the repaired tree"
fi
if [ "$reward" = 1 ]; then
  cp "$GOLDEN" /tmp/verify/setuptools/tests/test_config_discovery.py
  if ( cd /tmp/verify && PYTEST_ADDOPTS="" PYTHONPATH=/tmp/verify PYTHONDONTWRITEBYTECODE=1 \
       python3 -m pytest -p no:xdist -q $MODULES ) > /tmp/suite.log 2>&1; then
    echo "ok: project suite passed on the repaired tree with the golden overlay"
  else
    fail "the project's own suite is not green on the repaired tree"
  fi
  summary=$(grep -E "passed|failed|error" /tmp/suite.log | tail -2 | tr '\n' ' ')
  echo "    suite summary: ${summary:-see /tmp/suite.log}"
  if grep -qE "^[0-9]+ failed" /tmp/suite.log || grep -q INTERNALERROR /tmp/suite.log; then
    fail "suite reported failures:"
    grep -E "FAILED |INTERNALERROR" /tmp/suite.log | head -10 | sed 's/^/    /' >&2
    grep -B2 -A6 "INTERNALERROR" /tmp/suite.log | head -20 | sed 's/^/    /' >&2
  fi
  n_passed=$(grep -oE "[0-9]+ passed" /tmp/suite.log | grep -oE "^[0-9]+" | tail -1)
  if [ "${n_passed:-0}" -lt 200 ]; then
    fail "suspiciously few tests passed (${n_passed:-0}); suite may have been skipped"
  fi
fi

# ---------- 3. authored hidden cases -----------------------------------------
echo "== hidden cases =="
if [ "$reward" = 1 ]; then
  n_hidden=0
  for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    runner="$case/run.py"
    [ -f "$runner" ] || continue
    n_hidden=$((n_hidden + 1))
    cname=$(basename "$case")
    set +e
    ( cd "$case" && PYTHONPATH=/tmp/verify PYTHONDONTWRITEBYTECODE=1 python3 run.py ) > "/tmp/hidden-$cname.log" 2>&1
    rc=$?
    set -e
    if [ "$rc" = 0 ]; then
      echo "ok: hidden case $cname: $(tail -1 /tmp/hidden-$cname.log)"
    else
      fail "hidden case $cname failed (exit $rc)"
      tail -8 "/tmp/hidden-$cname.log" | sed 's/^/    /' >&2
    fi
  done
  if [ "$n_hidden" -lt 2 ]; then
    fail "fewer than two hidden cases were exercised"
  fi
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0