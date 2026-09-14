#!/bin/bash
# Verifier for dunnage-light: an upstream-clone debugging task on clap-rs/clap.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the list-of-conditions OS-string flavour of conditional default values
# silently drops every condition keyed by a plain argument id. The verifier:
#   0. asserts tree provenance: /app/src HEAD is still the pinned parent
#      commit, the upstream fix commit is reachable from neither /app/src nor
#      the verifier's pristine snapshot, the pristine snapshot is intact and
#      still carries the bug, the working tree differs from the parent only
#      in the source fix + the reproduction test + its registration, and the
#      overlaid upstream regression test is byte-identical;
echo "VERIFIER-USER:$(id -u):$(whoami)"
#   1. runs the agent's own reproduction test (a required deliverable)
#      against the pristine, unfixed tree and against the repaired tree:
#      it must FAIL on the former and PASS on the latter - a reproduction
#      that passes without the fix is vacuous;
#   2. rebuilds the project's own harness from the repaired tree and runs
#      the upstream regression test (shipped at tests/golden/, a verifier-only
#      mount that is never visible to the agent; byte-identical to the fix
#      commit's file, sha-pinned) plus two authored hidden cases
#      (a multi-condition list with ordering and the not-met negative, and a
#      condition keyed on a short flag) plus the whole builder suite.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
# The agent runs as root and shares the bind-mounted /logs/verifier dir with the
# verifier, so an adversarial agent could pre-plant a reward of 1. Wipe anything
# the agent planted before we compute the real reward, so that a verifier that is
# killed before its final write cannot inherit a planted 1.
rm -f /logs/verifier/reward.txt /logs/verifier/reward.json
reward=1

SRC=/app/src
PRISTINE=/opt/pristine
GOLDEN=/tests/golden/arg_settings.rs
PARENT_SHA=8bb3853eb5e19e9190d142ebb9ae230312da89f1
FIX_SHA=3eacf5b8b0f1e79955a0e7f94dc18b1f6a6b6502
GOLDEN_SHA=08a1fc63f7f4c4b3936c4353e18d869c1e64c439b3ac64615011fa5c5bc78778
REPRO_PATH=tests/builder/dunnage_repro.rs
# the deliverable is /app/src/tests/builder/dunnage_repro.rs
REPRO_FN=default_value_ifs_os_repro
GOLDEN_FN=default_value_ifs_os
MIN_FULL=1580

# The agent (root, sharing this container) can plant fake 'builder-*' wrapper
# scripts inside the gitignored target/ dirs of BOTH trees, with future mtimes,
# and the verifier's ls -t glob would pick them, lying about every test run.
# Wipe every builder artifact in both trees now; the cargo rebuilds below
# regenerate the genuine binaries, and harness_bin additionally refuses
# anything that is not a real ELF executable.
rm -f "$SRC/target/debug/deps/builder-"* "$PRISTINE/target/debug/deps/builder-"* 2>/dev/null || true
rm -f "$SRC/target/debug/deps/builder-"*".d" "$PRISTINE/target/debug/deps/builder-"*".d" 2>/dev/null || true

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

harness_bin() {  # harness_bin TREE : newest real ELF builder test binary
  local f bytes
  for f in $(ls -t "$1/target/debug/deps/builder-"* 2>/dev/null | grep -v '\.d$'); do
    # refuse anything that is not a genuine ELF executable (magic bytes \x7fELF)
    if [ -f "$f" ] && [ "$(head -c 4 "$f" 2>/dev/null)" = "$(printf '\177ELF')" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

run_test_expect_pass() {  # BIN TESTNAME LABEL
  local bin=$1 name=$2 label=$3 out
  out=$("$bin" --test "$name" 2>&1)
  local rc=$?
  if [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q "test result: ok." \
      && printf '%s\n' "$out" | grep -q "0 failed" \
      && printf '%s\n' "$out" | grep -Fq "$name ... ok"; then
    echo "ok: $label passes"
  else
    fail "$label"
    printf '%s\n' "$out" | tail -12 | sed 's/^/    /' >&2
  fi
}

run_test_expect_fail() {  # BIN TESTNAME LABEL
  local bin=$1 name=$2 label=$3 out
  out=$("$bin" --test "$name" 2>&1)
  local rc=$?
  if [ "$rc" != 0 ] && printf '%s\n' "$out" | grep -q "test result: FAILED" \
      && printf '%s\n' "$out" | grep -Fq "$name"; then
    echo "ok: $label fails against the unfixed tree"
  else
    fail "$label"
    printf '%s\n' "$out" | tail -12 | sed 's/^/    /' >&2
  fi
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
else
  head_now=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)
  if [ "$head_now" = "$PARENT_SHA" ]; then
    echo "ok: /app/src HEAD is the pinned parent commit"
  else
    fail "/app/src HEAD is not the pinned parent commit (got ${head_now:-missing})"
  fi
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from /app/src (the answer was fetched, not implemented)"
else
  echo "ok: fix commit not reachable from /app/src"
fi
if git -C "$PRISTINE" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the pristine snapshot"
else
  echo "ok: fix commit not reachable from the pristine snapshot"
fi

if [ -f "$GOLDEN" ] && [ "$(sha256sum < "$GOLDEN" | cut -d' ' -f1)" = "$GOLDEN_SHA" ]; then
  echo "ok: upstream regression test is byte-identical to the fix commit's"
else
  fail "upstream regression test missing or altered"
fi

if [ "$(git -C "$PRISTINE" rev-parse HEAD 2>/dev/null || true)" = "$PARENT_SHA" ] \
   && [ -z "$(git -C "$PRISTINE" status --porcelain 2>/dev/null || true)" ] \
   && grep -Fq 'self.default_value_if_os(arg.key(), *val, *default);' \
        "$PRISTINE/src/builder/arg.rs" 2>/dev/null; then
  echo "ok: pristine snapshot is the clean, unfixed parent state"
else
  fail "pristine snapshot was tampered with or is not carrying the bug"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
expected=$(printf '%s\n' \
  ' M src/builder/arg.rs' \
  ' M tests/builder/main.rs' \
  '?? tests/builder/dunnage_repro.rs' | sort)
if [ "$(printf '%s\n' "$porcelain" | sort)" = "$expected" ]; then
  echo "ok: working tree differs from the parent only in the fix, the reproduction test, and its registration"
else
  fail "unexpected working-tree changes:"
  printf '%s\n' "$porcelain" | head -20 | sed 's/^/    /' >&2
fi

if grep -q '^mod dunnage_repro;$' "$SRC/tests/builder/main.rs" 2>/dev/null \
   && [ -f "$SRC/$REPRO_PATH" ] \
   && grep -Fq "fn $REPRO_FN" "$SRC/$REPRO_PATH" 2>/dev/null; then
  echo "ok: reproduction test module is registered and carries the required test function"
else
  fail "reproduction test is missing, unregistered, or lacks fn $REPRO_FN"
fi

if [ "$(git -C "$SRC" diff --name-only -- src/ 2>/dev/null || true)" = "src/builder/arg.rs" ]; then
  echo "ok: the only source change is in src/builder/arg.rs"
else
  fail "unexpected source files changed (allowed: src/builder/arg.rs only)"
fi

if grep -Fq 'self.default_value_if_os(arg.key(), *val, *default);' "$SRC/src/builder/arg.rs" 2>/dev/null; then
  fail "the faulty double-hashed call is still present in src/builder/arg.rs"
else
  echo "ok: the faulty call is gone from the repaired source"
fi

# forward reference so the pristine run below can use the agent's repro file
if [ ! -f "$SRC/$REPRO_PATH" ]; then
  fail "reproduction test absent; cannot run the pre-fix check"
fi

# ---------- 1. repaired tree: golden + hidden + full suite --------------------
echo "== repaired tree: overlay upstream regression + hidden cases, rebuild =="
append_mod() {  # append_mod TREE MODULE
  local tree=$1 mod=$2
  grep -q "^mod $mod;$" "$tree/tests/builder/main.rs" || echo "mod $mod;" >> "$tree/tests/builder/main.rs"
}

n_hidden=0
mkdir -p /tmp/hidden-files
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  for f in "$case"*.rs; do
    [ -f "$f" ] || continue
    n_hidden=$((n_hidden + 1))
    base=$(basename "$f" .rs)
    cp "$f" "$SRC/tests/builder/$base.rs"
    cp "$f" "$PRISTINE/tests/builder/$base.rs"
    append_mod "$SRC" "$base"
    append_mod "$PRISTINE" "$base"
  done
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

cp "$GOLDEN" "$SRC/tests/builder/arg_settings.rs"
cp "$GOLDEN" "$PRISTINE/tests/builder/arg_settings.rs"
cp "$SRC/$REPRO_PATH" "$PRISTINE/$REPRO_PATH"
append_mod "$PRISTINE" dunnage_repro

if ( cd "$SRC" && timeout 900 cargo test --no-run -p clap > /tmp/verify-src-build.log 2>&1 ); then
  echo "ok: repaired tree builds"
else
  fail "repaired tree does not build"
  tail -20 /tmp/verify-src-build.log | sed 's/^/    /' >&2
fi

BIN_SRC=$(harness_bin "$SRC")
echo "== upstream regression test on the repaired tree =="
run_test_expect_pass "$BIN_SRC" "$GOLDEN_FN" "upstream regression test (golden)"
echo "== agent's own reproduction on the repaired tree =="
run_test_expect_pass "$BIN_SRC" "$REPRO_FN" "agent's reproduction test"
echo "== authored hidden cases on the repaired tree =="
run_test_expect_pass "$BIN_SRC" dunnage_hidden_multi_conditions "hidden case: multi-condition list with precedent order and not-met negative"
run_test_expect_pass "$BIN_SRC" dunnage_hidden_short_condition "hidden case: condition keyed on a short flag, including not-met negative"

echo "== whole builder suite on the repaired tree =="
full_out=$("$BIN_SRC" 2>&1)
full_rc=$?
full_passed=$(printf '%s\n' "$full_out" | grep -oE '[0-9]+ passed' | tail -1 | grep -oE '^[0-9]+')
if [ "$full_rc" = 0 ] && printf '%s\n' "$full_out" | grep -q 'test result: ok.' \
   && printf '%s\n' "$full_out" | grep -q '0 failed' \
   && [ "${full_passed:-0}" -ge "$MIN_FULL" ]; then
  echo "ok: whole builder suite green (${full_passed:-?} passed)"
else
  fail "whole builder suite is not green"
  printf '%s\n' "$full_out" | tail -8 | sed 's/^/    /' >&2
fi

# ---------- 2. pristine (unfixed) tree: the reproduction must fail there ------
echo "== pre-fix tree concept: rebuild pristine snapshot with the agent's repro =="
if ( cd "$PRISTINE" && timeout 900 cargo test --no-run -p clap > /tmp/verify-pristine-build.log 2>&1 ); then
  echo "ok: pristine tree builds with the agent's reproduction overlaid"
else
  fail "agent's reproduction does not build against the unfixed tree"
  tail -20 /tmp/verify-pristine-build.log | sed 's/^/    /' >&2
fi

BIN_PRI=$(harness_bin "$PRISTINE")
echo "== upstream regression test must fail on the unfixed tree =="
run_test_expect_fail "$BIN_PRI" "$GOLDEN_FN" "upstream regression test on the unfixed tree"
echo "== agent's reproduction must fail on the unfixed tree =="
run_test_expect_fail "$BIN_PRI" "$REPRO_FN" "agent's reproduction on the unfixed tree"

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0