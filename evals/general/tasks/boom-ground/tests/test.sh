#!/bin/bash
# Verifier for boom-ground: upstream-clone debugging task on tmux/tmux.
#
# Contract. The agent must fix, in the real checkout at /app/src, a real
# upstream bug: respawning a pane while a control-mode client is behind on it
# leaves stale control offsets pointing into the replaced screen buffer and the
# server crashes a moment later (upstream issue #5498, fixed by commit
# 4714f478: control_reset_pane() called from spawn_pane()). The deliverable
# /app/repro.sh must be a standalone sh script honouring $TEST_TMUX that exits
# 0 iff the server survives a respawn of a pane its control clients are behind
# on. The verifier:
#   0. asserts the deliverables exist (repro script, git checkout, binary);
#   1. asserts tree provenance (HEAD == pinned base, the fix and fix-merge
#      commit objects are unreachable, the only tracked working-tree changes
#      are a non-empty subset of control.c/spawn.c/tmux.h, the pristine parent
#      snapshot /opt/prefix/src matches HEAD, the golden test and the regress
#      slice scripts carry their pinned hashes);
#   2. rebuilds /app/src in place from the agent's sources (touch changed
#      files, make -j1) and requires the build to succeed;
#   3. runs the agent's own reproduction with TEST_TMUX=/opt/prefix/tmux (the
#      pristine BUGGY build, snapshotted at image build time) and requires it
#      to FAIL, then with TEST_TMUX=/app/src/tmux (the repaired build) and
#      requires it to PASS;
#   4. runs the project's own regression test for this bug (extracted from the
#      fix-side tree at image build time into /opt/golden) against the
#      repaired build and requires it to pass;
#   5. runs five of tmux's own regress scripts (pane-ops, window-ops,
#      control-client-sanity, capture-pane-sgr0, pipe-pane) against the
#      repaired build and requires each to stay green;
#   6. runs two authored hidden cases (silent-origin moved-window respawn;
#      three clients with a doubled respawn of a moved pane) - inputs the
#      upstream test does not use - and requires each to FAIL against the
#      pristine buggy build and PASS against the repaired build.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
REPRO=/app/repro.sh
BASE_SHA=19a085a6727650ae660196a38e1a412f1b386615
FIX_SHA=4714f478fed87ae2c510ecd035aa89c5a90dedf8
MERGE_SHA=22b36797526758ff3ed3407c1bbc3cde26277aaf
GOLDEN=/opt/golden/respawn-pane-control-lag.sh
GOLDEN_SHA=a0aeeb2719cc163664d2e535ed74731a90c596c10534b12b3cdad1d5d064372d
PRISTINE=/opt/prefix
ALLOW=( control.c spawn.c tmux.h )
SLICE=( pane-ops.sh window-ops.sh control-client-sanity.sh capture-pane-sgr0.sh pipe-pane.sh )
declare -A SLICE_SHA=(
  [pane-ops.sh]=918d255217b86162f771ac4ba57422a5829946dec8128fed1a6c1d68453d554a
  [window-ops.sh]=db08addba0007eda7cf4def68bab3c316fda7f34da9d71075a14127fb46924c3
  [control-client-sanity.sh]=f90e0bab9e2bdeda16ce6e91bf4cb475397b8b4d4189e46c36dd9665fa5cd002
  [capture-pane-sgr0.sh]=32d9f07e5c8663cc602844398d14719fa891f80ab8f6bcc445afd21601f6a3d5
  [pipe-pane.sh]=6a9c86cb7b0ddbc8b65d5638444e3a7e2e7384978e1aa7f00c312cd77aab96e5
)

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0. deliverables present -------------------------------------------
echo "== deliverables =="
if [ -f "$REPRO" ]; then
  echo "ok: $REPRO exists"
else
  fail "deliverable $REPRO does not exist"
fi
if [ -d "$SRC/.git" ]; then
  echo "ok: /app/src is a git checkout"
else
  fail "deliverable /app/src is not a git checkout"
fi
if [ -x "$SRC/tmux" ]; then
  echo "ok: /app/src/tmux exists and is executable"
else
  fail "no tmux binary at /app/src/tmux"
fi

# ---------- 1. tree provenance --------------------------------------------------
echo "== tree provenance =="
cur_head=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)
if [ "$cur_head" = "$BASE_SHA" ]; then
  echo "ok: HEAD is the pinned base commit"
else
  fail "HEAD is not the pinned base commit (got ${cur_head:-none})"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the fix commit object is not present in the working clone"
fi
if git -C "$SRC" cat-file -e "${MERGE_SHA}^{commit}" 2>/dev/null; then
  fail "the fix-merge commit is reachable from the working clone"
else
  echo "ok: the fix-merge commit object is not present in the working clone"
fi

changed=$(git -C "$SRC" diff HEAD --name-only 2>/dev/null || true)
if [ -z "$changed" ]; then
  fail "no tracked source changes under /app/src - the bug was not fixed"
else
  ok_allow=1
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case " ${ALLOW[*]} " in
      *" $f "*) : ;;
      *) echo "    unexpected tracked change: $f" >&2; ok_allow=0 ;;
    esac
  done <<EOF
$changed
EOF
  if [ "$ok_allow" = 1 ]; then
    echo "ok: only the minimal fix files changed"
  else
    fail "tracked changes outside the minimal fix set"
  fi
fi
porcelain=$(git -C "$SRC" status --porcelain --untracked-files=no 2>/dev/null || true)
if [ -n "$porcelain" ]; then
  newporc=$(printf '%s\n' "$porcelain" | grep -vE '^( M|M |MM) (control\.c|spawn\.c|tmux\.h)$' || true)
  if [ -n "$newporc" ]; then
    fail "unexpected working-tree changes:"
    printf '%s\n' "$newporc" | head -10 | sed 's/^/    /' >&2
  else
    echo "ok: reported working-tree changes are confined to the fix files"
  fi
fi

# pristine parent snapshot must still byte-match HEAD (detects tampering)
for f in control.c spawn.c tmux.h; do
  psha=$(sha256sum "$PRISTINE/src/$f" 2>/dev/null | cut -d' ' -f1 || true)
  hsha=$(git -C "$SRC" show "HEAD:$f" 2>/dev/null | sha256sum | cut -d' ' -f1 || true)
  if [ -n "$psha" ] && [ "$psha" = "$hsha" ]; then
    echo "ok: pristine snapshot /opt/prefix/src/$f matches HEAD"
  else
    fail "pristine snapshot /opt/prefix/src/$f was altered or is missing"
  fi
done

gsha=$(sha256sum "$GOLDEN" 2>/dev/null | cut -d' ' -f1 || true)
if [ "$gsha" = "$GOLDEN_SHA" ]; then
  echo "ok: golden regression test carries the pinned hash"
else
  fail "golden regression test is missing or was altered (${gsha:-missing})"
fi

for s in "${SLICE[@]}"; do
  ssha=$(sha256sum "$PRISTINE/src/regress/$s" 2>/dev/null | cut -d' ' -f1 || true)
  if [ "$ssha" = "${SLICE_SHA[$s]}" ]; then
    echo "ok: slice script regress/$s carries the pinned hash"
  else
    fail "slice script regress/$s is missing or was altered (${ssha:-missing})"
  fi
done

# ---------- 2. rebuild from the agent's sources --------------------------------
echo "== rebuild /app/src in place =="
if [ -d "$SRC/.git" ] && [ -n "$changed" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    touch "$SRC/$f" 2>/dev/null || true
  done <<EOF
$changed
EOF
  ( cd "$SRC" && make -j1 >/tmp/rebuild.out 2>&1 )
  rc_make=$?
  if [ "$rc_make" -eq 0 ] && [ -x "$SRC/tmux" ]; then
    echo "ok: make completed (exit $rc_make) and /app/src/tmux exists"
  else
    fail "the tree did not rebuild (make exit $rc_make)"
    tail -12 /tmp/rebuild.out | sed 's/^/    /' >&2
  fi
else
  fail "cannot rebuild: no git checkout or no source changes"
fi

# ---------- 3. the agent's own reproduction, both directions -------------------
echo "== reproduction against the pristine BUGGY build (must FAIL) =="
if [ -f "$REPRO" ]; then
  TEST_TMUX="$PRISTINE/tmux" sh "$REPRO" >/tmp/repro-prefix.out 2>&1
  rc_prefix=$?
  if [ "$rc_prefix" -ne 0 ]; then
    echo "ok: reproduction failed on the buggy build (exit $rc_prefix): $(tail -1 /tmp/repro-prefix.out)"
  else
    fail "the reproduction PASSED on the pristine buggy build - it does not demonstrate the bug"
    tail -5 /tmp/repro-prefix.out | sed 's/^/    /' >&2
  fi

  echo "== reproduction against the repaired build (must PASS) =="
  TEST_TMUX="$SRC/tmux" sh "$REPRO" >/tmp/repro-fixed.out 2>&1
  rc_fixed=$?
  if [ "$rc_fixed" -eq 0 ]; then
    echo "ok: reproduction passed on the repaired build"
  else
    fail "the reproduction FAILED on the repaired build (exit $rc_fixed):"
    tail -5 /tmp/repro-fixed.out | sed 's/^/    /' >&2
  fi

  # The reproduction must fail on the buggy build no matter where that binary
  # lives. A script that only discriminates on TEST_TMUX's path is hardcoding
  # the expected result, not reproducing the bug, so re-run it against a
  # renamed copy of the pristine buggy build.
  moved_dir=/tmp/repro-moved-$$
  mkdir -p "$moved_dir"
  if cp "$PRISTINE/tmux" "$moved_dir/pristine-tmux" \
      && chmod +x "$moved_dir/pristine-tmux"; then
    TEST_TMUX="$moved_dir/pristine-tmux" sh "$REPRO" >/tmp/repro-moved.out 2>&1
    rc_moved=$?
    if [ "$rc_moved" -ne 0 ]; then
      echo "ok: reproduction failed on the buggy build at a moved path (exit $rc_moved)"
    else
      fail "the reproduction PASSED against a renamed copy of the buggy build - it is hardcoded to the pristine path, not a real reproduction"
      tail -5 /tmp/repro-moved.out | sed 's/^/    /' >&2
    fi
  else
    fail "could not prepare the moved-path buggy binary for the reproduction check"
  fi
  rm -rf "$moved_dir"
else
  fail "reproduction checks skipped: $REPRO missing"
fi

if [ "$reward" = 1 ]; then
  # ---------- 4. the project's own regression test -----------------------------
  echo "== upstream regression test (respawn-pane-control-lag.sh) =="
  TEST_TMUX="$SRC/tmux" sh "$GOLDEN" >/tmp/golden.out 2>&1
  rc_golden=$?
  if [ "$rc_golden" -eq 0 ]; then
    echo "ok: regression test passed (exit 0)"
  else
    fail "the project's own regression test does not pass (exit $rc_golden):"
    tail -8 /tmp/golden.out | sed 's/^/    /' >&2
  fi

  # ---------- 5. project suite slice (fix broke nothing else) -------------------
  echo "== project regress slice =="
  n_slice=0
  for s in "${SLICE[@]}"; do
    n_slice=$((n_slice + 1))
    TEST_TMUX="$SRC/tmux" TERM=screen sh "$PRISTINE/src/regress/$s" >"/tmp/slice-$s.out" 2>&1
    rc_s=$?
    if [ "$rc_s" -eq 0 ]; then
      echo "ok: regress/$s (exit 0)"
    else
      fail "regress/$s failed (exit $rc_s):"
      tail -6 "/tmp/slice-$s.out" | sed 's/^/    /' >&2
    fi
  done
  [ "$n_slice" -ge 3 ] || fail "too few slice scripts ran ($n_slice)"

  # ---------- 6. authored hidden cases ------------------------------------------
  echo "== hidden cases =="
  n_hidden=0
  for case in /tests/hidden/*/; do
    [ -d "$case" ] || continue
    n_hidden=$((n_hidden + 1))
    cname=$(basename "$case")
    if [ ! -f "$case/run.sh" ]; then
      fail "hidden case $cname has no run.sh"
      continue
    fi
    ( cd /app && timeout 240 env TEST_TMUX="$PRISTINE/tmux" sh "$case/run.sh" ) >"/tmp/hidden-$cname-prefix.out" 2>&1
    rc_p=$?
    if [ "$rc_p" -ne 0 ]; then
      echo "ok: hidden case $cname fails on the buggy build (exit $rc_p)"
    else
      fail "hidden case $cname PASSED on the buggy build - it does not generalise the repro"
    fi
    ( cd /app && timeout 240 env TEST_TMUX="$SRC/tmux" sh "$case/run.sh" ) >"/tmp/hidden-$cname-fixed.out" 2>&1
    rc_f=$?
    if [ "$rc_f" -eq 0 ] && grep -q "HIDDEN CASE .*: ok" "/tmp/hidden-$cname-fixed.out"; then
      echo "ok: hidden case $cname passes on the repaired build"
    else
      fail "hidden case $cname failed on the repaired build (exit $rc_f):"
      tail -6 "/tmp/hidden-$cname-fixed.out" | sed 's/^/    /' >&2
    fi
  done
  if [ "$n_hidden" -lt 2 ]; then
    fail "fewer than two hidden cases were exercised"
  fi
fi

echo
echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0