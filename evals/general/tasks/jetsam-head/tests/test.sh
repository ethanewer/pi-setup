#!/bin/bash
# Verifier for jetsam-head: an upstream-clone debugging task on libvips.
#
# The agent must repair, in the real checkout at /app/src, a real upstream
# bug: icc_import of a float (0..1) RGB image produces all-black output
# (upstream issue #5123, fixed upstream by 736059b2e8e3ca84012b68a9ffdc3528bdeb1e8f;
# neither the issue ref nor the fix is revealed to the agent). The image's
# system-wide libvips (/usr) is byte-identical to the pristine parent build,
# so "pre-fix" runs use the default loader path and "repaired" runs use
# LD_LIBRARY_PATH=/app/src/build/libvips after a full clean rebuild from the
# agent's tree. The verifier:
#   0. asserts tree provenance (HEAD is the pinned parent, the upstream fix
#      commit is not reachable, tracked modifications under libvips/ only,
#      no untracked files, /usr libvips still the pristine parent build, and
#      /opt/golden still byte-identical to the fix-commit extraction);
#   1. runs the agent's own reproduction /app/reproduce.py against the
#      pristine parent build (must detect the bug: non-zero exit) and against
#      the rebuilt repaired tree (must exit 0);
#   2. rebuilds everything from the agent's tree with ninja (clean + -j1),
#      overlays the upstream regression test as test_golden_float.py and
#      requires it to pass, then requires the project's own test_colour.py
#      and test_conversion.py suites to pass in full;
#   3. runs the authored hidden cases (different fixture / different band
#      format / synthetic colours the upstream test does not use) against the
#      pristine parent build (must fail: non-vacuous) and against the rebuilt
#      tree (must pass).
#
# Review-hardening (jetsam-head wave):
#   - hidden-case scripts are sha-pinned; an agent that edits /tests/hidden/*/run.py
#     (the container runs as root and /tests is a per-trial writable copy) can no
#     longer make the hidden cases pass while the bug stands — the tampered hash is
#     caught here and the whole trial scores 0.
#   - both pytest invocations force `-o addopts=` so an agent-planted pytest.ini
#     (e.g. hidden with .git/info/exclude) cannot deselect the regression test or
#     the project suite. This closed a demonstrated bypass where the upstream
#     regression test was skipped ('6 passed, 1 deselected', exit 0) on an unfixed
#     tree.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=f0c38f9a7d4bea39e1e1718db2b441c91880a871
FIX_SHA=736059b2e8e3ca84012b68a9ffdc3528bdeb1e8f
GOLDEN=/opt/golden/test_colour.py
GOLDEN_SHA=8f7494f7bb8a6eb4a50a70daedee26ecbdb6f53509f4128d28019bfa24cdcced
USR_VIPS_SHA=df0e51353231c22e8d480910dbf2b199abe2629da0ee8f2f6bf82966f70b1b35
BUILD_LIB=/app/src/build/libvips
REPRO=/app/reproduce.py

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
clean_status=1
if [ -z "$porcelain" ]; then
  fail "the deliverable /app/src is unchanged (no repair was implemented)"
  clean_status=0
else
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      " M libvips/"*|"M  libvips/"*|"MM libvips/"*) : ;;
      *)
        fail "unexpected working-tree change: [$line] (want only ' M libvips/...' lines)"
        clean_status=0
        ;;
    esac
  done <<EOF
$porcelain
EOF
  if [ "$clean_status" = 1 ]; then
    echo "ok: working tree differs from the pinned commit only under libvips/:"
    printf '%s\n' "$porcelain" | sed 's/^/    /'
  fi
fi

usr_sha=$(sha256sum /usr/lib/x86_64-linux-gnu/libvips.so.42 2>/dev/null | cut -d' ' -f1)
if [ "$usr_sha" = "$USR_VIPS_SHA" ]; then
  echo "ok: system /usr libvips.so.42 is byte-identical to the pristine parent build"
else
  fail "system /usr libvips.so.42 was altered (${usr_sha:-missing}), expected $USR_VIPS_SHA"
fi

golden_sha=$(sha256sum "$GOLDEN" 2>/dev/null | cut -d' ' -f1)
if [ "$golden_sha" = "$GOLDEN_SHA" ]; then
  echo "ok: /opt/golden regression test is byte-identical to the fix-commit extraction"
else
  fail "/opt/golden regression test was altered (${golden_sha:-missing})"
fi

# Hidden-case fixtures are pinned so /tests/hidden/*/run.py cannot be replaced
# with a stub that exits 0 whenever LD_LIBRARY_PATH is set (demonstrated bypass).
for run in /tests/hidden/*/run.py; do
  [ -f "$run" ] || continue
  cname=$(basename "$(dirname "$run")")
  case "$cname" in
    case-png)   want=ea6ecef9d522a8f71a5e199fa2357f9063f71e6d28d199ce110e351893d71bd2 ;;
    case-double) want=33bf1dfb655b540ff5e5220785e2a6f61517ff3d22abad615f0c19034bf48cf6 ;;
    *)          want= ;;
  esac
  if [ -z "$want" ]; then
    fail "unexpected hidden case script: $run"
  else
    got=$(sha256sum "$run" | cut -d' ' -f1)
    if [ "$got" = "$want" ]; then
      echo "ok: hidden case $cname is byte-identical to the authored fixture"
    else
      fail "hidden case $cname was altered (hash ${got:-missing}, expected $want)"
    fi
  fi
done

# ---------- 1. the agent's own reproduction, both directions -----------------
echo "== the agent's reproduction =="
if [ ! -f "$REPRO" ]; then
  fail "the deliverable /app/reproduce.py does not exist"
elif [ ! -x "$REPRO" ]; then
  fail "the deliverable /app/reproduce.py is not executable"
elif ! grep -q "pyvips" "$REPRO" || ! grep -q "icc_import" "$REPRO"; then
  fail "/app/reproduce.py does not exercise pyvips icc_import (stub rejection)"
else
  echo "ok: /app/reproduce.py exists, is executable, and is a pyvips script"
fi

if [ "$reward" = 1 ]; then
  set +e
  env -u LD_LIBRARY_PATH -u VIPSHOME -u LD_PRELOAD python3 "$REPRO" > /tmp/repro-prefix.out 2>&1
  rc_pre=$?
  set -e
  if [ "$rc_pre" -ne 0 ]; then
    echo "ok: reproduction detects the bug on the pristine parent build (exit $rc_pre):"
    tail -3 /tmp/repro-prefix.out | sed 's/^/    /'
  else
    fail "reproduction exited 0 against the pristine parent build — it does not reproduce the bug"
    tail -3 /tmp/repro-prefix.out | sed 's/^/    /' >&2
  fi
fi

# ---------- 2. full clean rebuild from the agent's tree ----------------------
echo "== clean rebuild from the repaired tree =="
( cd "$SRC" && ninja -C build -j1 clean > /tmp/clean.log 2>&1 ) || true
if ( cd "$SRC" && ninja -C build -j1 > /tmp/rebuild.log 2>&1 ); then
  echo "ok: full rebuild (ninja -C build clean && ninja -C build -j1) succeeded"
else
  fail "full rebuild failed"
  tail -30 /tmp/rebuild.log | sed 's/^/    /' >&2
fi

if [ "$reward" = 1 ]; then
  set +e
  LD_LIBRARY_PATH="$BUILD_LIB" python3 "$REPRO" > /tmp/repro-fixed.out 2>&1
  rc_fixed=$?
  set -e
  if [ "$rc_fixed" -eq 0 ]; then
    echo "ok: reproduction passes on the rebuilt repaired tree:"
    tail -3 /tmp/repro-fixed.out | sed 's/^/    /'
  else
    fail "reproduction failed against the rebuilt tree (exit $rc_fixed) — the repair is not complete"
    tail -5 /tmp/repro-fixed.out | sed 's/^/    /' >&2
  fi
fi

# ---------- 3. the upstream regression test and the project's own suite ------
echo "== upstream regression test (test_icc_float_input) =="
if [ "$reward" = 1 ]; then
  cp "$GOLDEN" "$SRC/test/test-suite/test_golden_float.py"
  set +e
  ( cd "$SRC/test/test-suite" && LD_LIBRARY_PATH="$BUILD_LIB" \
        python3 -m pytest test_golden_float.py -q -p no:cacheprovider -o addopts= \
        > /tmp/golden.out 2>&1 )
  rc_golden=$?
  set -e
  rm -f "$SRC/test/test-suite/test_golden_float.py"
  if [ "$rc_golden" -eq 0 ]; then
    echo "ok: upstream regression test passes on the repaired tree ($(tail -1 /tmp/golden.out))"
  else
    fail "upstream regression test did not pass on the repaired tree (pytest exit $rc_golden)"
    tail -15 /tmp/golden.out 2>/dev/null | sed 's/^/    /' >&2
  fi
fi

echo "== project's own colour and conversion suites =="
if [ "$reward" = 1 ]; then
  set +e
  ( cd "$SRC/test/test-suite" && LD_LIBRARY_PATH="$BUILD_LIB" \
        python3 -m pytest test_colour.py test_conversion.py -q -p no:cacheprovider -o addopts= \
        > /tmp/suite.out 2>&1 )
  rc_suite=$?
  set -e
  if [ "$rc_suite" -eq 0 ]; then
    echo "ok: project suite fully green on the repaired tree ($(tail -1 /tmp/suite.out))"
  else
    fail "the project's own suite is not fully green on the repaired tree (pytest exit $rc_suite)"
    tail -15 /tmp/suite.out 2>/dev/null | sed 's/^/    /' >&2
  fi
fi

# ---------- 4. authored hidden cases -----------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  run="$case/run.py"
  [ -f "$run" ] || continue
  n_hidden=$((n_hidden + 1))
  cname=$(basename "$case")

  # non-vacuous: must detect the bug on the pristine parent build
  set +e
  env -u LD_LIBRARY_PATH -u VIPSHOME python3 "$run" > "/tmp/hidden-$cname-pre.out" 2>&1
  rc_pre=$?
  set -e
  if [ "$rc_pre" -ne 0 ]; then
    echo "ok: hidden case $cname detects the bug on the pristine parent build"
  else
    fail "hidden case $cname passed against the pristine parent build (vacuous case)"
    cat "/tmp/hidden-$cname-pre.out" | tail -3 | sed 's/^/    /' >&2
  fi

  # the real assertion: must pass on the rebuilt repaired tree
  set +e
  LD_LIBRARY_PATH="$BUILD_LIB" python3 "$run" > "/tmp/hidden-$cname.out" 2>&1
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "ok: hidden case $cname on repaired tree: $(tail -1 "/tmp/hidden-$cname.out")"
  else
    fail "hidden case $cname failed on the repaired tree (exit $rc)"
    tail -6 "/tmp/hidden-$cname.out" 2>/dev/null | sed 's/^/    /' >&2
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0