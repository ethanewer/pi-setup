#!/bin/bash
# Verifier for ballast-current: an upstream-clone debugging task on
# astral-sh/uv.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the on-disk HTTP cache entry reader panics with `attempt to add with
# overflow` when a corrupt entry's trailing length marker decodes to
# usize::MAX, instead of rejecting the entry as an ArchiveRead error.
# The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the clone, the regression
#      test the image overlays into crates/uv-client/tests/it/ is
#      byte-identical to the upstream regression test, the HTTP cache
#      reader source holds a non-empty diff, and nothing else inside the
#      repository changed);
#   1. rebuilds the uv-client `it` test harness from the repaired tree and
#      requires the project's own regression test to pass:
#        cargo test -p uv-client --test it cached_client::reject_overflowing_cache_policy_length -- --exact
#   2. requires the offline part of the project's own integration suite to
#      stay green: cargo test -p uv-client --test it -- cached_client
#      proxy ssl_certs user_agent_version (26 tests; remote_metadata needs
#      network access and is not part of the grade);
#   3. injects the authored hidden-case modules into tests/it and requires
#      them all to pass: corrupt entries with other overflowing length
#      markers (bare trailers and payload-prefixed trailers) must yield
#      ArchiveRead errors instead of panics, and a real cache entry produced
#      by uv's own cache writer must still load with its data intact.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=6353b242d2774244ae2c6b4be1b95c70f84e97ab
FIX_SHA=48c4357fe2517cce464ffa040d75c92be6a7dc71
GOLDEN_CACHED_SHA=e2da48bae43b157a823e5d4f4d1314e1e474740633f5a5c3663cd7777800c7c1
GOLDEN_MAIN_SHA=450c77a2a29294de7f95cd47e0d620c8c685cbbc48bc124a359aea8523ba2ad4

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

if [ -z "$(git -C "$SRC" diff -- crates/uv-client/src/cached_client.rs 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: crates/uv-client/src/cached_client.rs differs from the pinned commit"
fi

if grep -qF "len_usize + 8" "$SRC/crates/uv-client/src/cached_client.rs" 2>/dev/null; then
  fail "the overflowing cache-policy length arithmetic is still present (no real fix)"
else
  echo "ok: overflowing cache-policy length arithmetic removed from the reader"
fi

want_cargo=$(cat /opt/golden/cargo.sha256 2>/dev/null || true)
got_cargo=$(sha256sum "$(command -v cargo 2>/dev/null)" 2>/dev/null | cut -d' ' -f1)
if [ -z "$want_cargo" ] || [ "$got_cargo" != "$want_cargo" ]; then
  fail "the cargo binary does not match the image-build digest (a wrapper may be shadowing it)"
else
  echo "ok: cargo is the pristine image-build binary"
fi

for f in crates/uv-client/tests/it/cached_client.rs crates/uv-client/tests/it/main.rs; do
  want="$GOLDEN_CACHED_SHA"
  [ "$f" = "crates/uv-client/tests/it/main.rs" ] && want="$GOLDEN_MAIN_SHA"
  have=$(sha256sum < "$SRC/$f" 2>/dev/null | cut -d' ' -f1)
  if [ "$have" = "$want" ]; then
    echo "ok: $f is byte-identical to the upstream regression test"
  else
    fail "$f was altered (${have:-missing})"
  fi
done

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
unexpected=0
if [ -n "$porcelain" ]; then
  while IFS= read -r line; do
    case "$line" in
      ""|" M crates/uv-client/src/cached_client.rs"|" M crates/uv-client/tests/it/main.rs"|"?? crates/uv-client/tests/it/cached_client.rs")
        ;;
      *)
        unexpected=1
        echo "  unexpected: '$line'" >&2
        ;;
    esac
  done <<< "$porcelain"
fi
if [ "$unexpected" = 1 ]; then
  fail "working tree contains changes other than the fix and the overlaid regression test"
else
  echo "ok: working tree differs from the pinned commit only in the fix and the overlaid regression test"
fi

# ---------- 1. rebuild and run the upstream regression test ------------------
echo "== rebuild + upstream regression test =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && cargo test -p uv-client --test it cached_client::reject_overflowing_cache_policy_length -- --exact > /tmp/golden.out 2>&1 ); then
    :
  fi
  if grep -qF "cached_client::reject_overflowing_cache_policy_length ... ok" /tmp/golden.out 2>/dev/null \
     && grep -qF "1 passed; 0 failed" /tmp/golden.out 2>/dev/null; then
    echo "ok: upstream regression test passes (1 passed; 0 failed)"
  else
    fail "upstream regression test did not pass"
    tail -25 /tmp/golden.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 2. offline part of the project's own integration suite -----------
echo "== project's own offline integration suite =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && cargo test -p uv-client --test it -- cached_client proxy ssl_certs user_agent_version > /tmp/suite.out 2>&1 ); then
    :
  fi
  if grep -qF "26 passed; 0 failed" /tmp/suite.out 2>/dev/null \
     && grep -qF "cached_client::reject_overflowing_cache_policy_length ... ok" /tmp/suite.out 2>/dev/null; then
    echo "ok: offline it suite green: 26 passed; 0 failed"
  else
    fail "the offline integration suite is not green"
    tail -25 /tmp/suite.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 3. authored hidden cases -----------------------------------------
echo "== hidden cases =="
if [ "$reward" = 1 ]; then
  n_hidden=0
  hnames=""
  for dir in /tests/hidden/*/; do
    [ -d "$dir" ] || continue
    for f in "$dir"*.rs; do
      [ -f "$f" ] || continue
      base=$(basename "$f" .rs)
      n_hidden=$((n_hidden + 1))
      cp "$f" "$SRC/crates/uv-client/tests/it/$base.rs"
      if ! grep -q "mod $base;" "$SRC/crates/uv-client/tests/it/main.rs"; then
        printf 'mod %s;\n' "$base" >> "$SRC/crates/uv-client/tests/it/main.rs"
      fi
      hnames="$hnames $base"
    done
  done
  if [ "$n_hidden" -lt 2 ]; then
    fail "fewer than two hidden cases were injected"
  elif ( cd "$SRC" && cargo test -p uv-client --test it -- $hnames > /tmp/hidden.out 2>&1 ); then
    :
    if grep -qF "test result: ok." /tmp/hidden.out 2>/dev/null \
       && [ "$(grep -cE '^test hc_.* \.\.\. ok$' /tmp/hidden.out)" -ge 5 ]; then
      echo "ok: hidden cases all pass ($(grep -cE '^test hc_.* \.\.\. ok$' /tmp/hidden.out) tests)"
    else
      fail "hidden cases did not all pass"
      tail -30 /tmp/hidden.out 2>/dev/null | sed 's/^/    /' >&2 || true
    fi
  else
    fail "hidden-case build/run failed"
    tail -30 /tmp/hidden.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0