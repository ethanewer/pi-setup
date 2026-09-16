#!/bin/bash
# Verifier for capstan-keel: an upstream-clone debugging task on astral-sh/uv.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# `uv cache clean` / `uv cache prune` report the logical byte length of the
# removed entries as the reclaimed space instead of the allocated disk blocks,
# and they do not de-duplicate hard links (an entry whose storage is shared
# with a surviving file elsewhere frees 0 bytes, yet is reported at full
# length; sparse holes are charged as data; 0 bytes reclaimed prints no figure
# at all).  The verifier:
#   0. asserts the golden upstream regression-test bytes (extracted at image
#      build time from the fix commit into /opt/golden/) are intact;
#   1. asserts tree provenance: HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, only the
#      crates involved in cache-removal accounting were modified, at least one
#      source file is actually repaired, and nothing was added;
#   2. builds the project (offline; the image ships a warm target dir);
#   3. runs the project's own regression test for this bug against the
#      repaired tree.  The upstream fix renamed the internal accounting API,
#      so the extracted golden test only compiles when the tree reproduces the
#      rename; a functionally-correct fix that keeps the parent names is
#      exercised through the build-time name-translated variant.  Either way,
#      the SAME behavioural assertions run (blocks-based, hard-link-aware,
#      sparse-aware accounting);
#   4. runs the project's own existing uv-cache and uv-fs crate suites,
#      proving the fix broke nothing else;
#   5. runs three authored hidden end-to-end scenarios (retained hard links at
#      depth, a hard link mixed with an independent file, and a sparse file
#      next to a small file) against the rebuilt binary, comparing the printed
#      `(SIZE)` figure with an independently computed expectation derived only
#      from filesystem metadata (st_blocks * 512 when the final link count is
#      1, sum, IEC-formatted).
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
UV_BIN="$SRC/target/debug/uv"
PARENT_SHA=64c73b115b544e8424a8c69f44131e21d66e629c
FIX_SHA=fab2c0c0d2992217ff8768d11558f4b668d02501
GOLDEN_DIR=/opt/golden
GOLDEN_REMOVAL_SHA256=ebc8b3cc70495ddaae21244345ed0d471950936df60ccb973bcb3a3325cdb825
GOLDEN_LEGACY_SHA256=f2bd39047e27904290015a2e8b340f4bb05e722ecabf745820cdcbfec9b3ec3a
GOLDEN_CLEAN_SHA256=067d8a445a2188de66ce2717c2492c9f5f5a20987db2b5a6dd4c4ca15154d4aa
GOLDEN_PRUNE_SHA256=0e5dd715049eec0524f7fbaffbac2717b88482d2bd4856ff69bf313bcedb99df
ALLOWED_MODIFIED='^ M (crates/uv-cache/src/removal\.rs|crates/uv-cache/src/lib\.rs|crates/uv-fs/src/lib\.rs|crates/uv-fs/src/space\.rs|crates/uv/src/commands/cache_clean\.rs|crates/uv/src/commands/cache_prune\.rs)$'

fail() {
  echo "FAIL: $*" >&2
  reward=0
}

# ---------------------------------------------------------------- 0. golden --
echo "== 0. golden upstream regression tests intact =="
for pair in \
    "removal.rs:$GOLDEN_REMOVAL_SHA256" \
    "removal_legacy_api.rs:$GOLDEN_LEGACY_SHA256" \
    "cache_clean.rs:$GOLDEN_CLEAN_SHA256" \
    "cache_prune.rs:$GOLDEN_PRUNE_SHA256"; do
  name="${pair%%:*}"
  want="${pair##*:}"
  if [ -f "$GOLDEN_DIR/$name" ]; then
    got="$(sha256sum "$GOLDEN_DIR/$name" | awk '{print $1}')"
    if [ "$got" = "$want" ]; then
      echo "ok: golden $name digest matches"
    else
      fail "golden $name digest mismatch (expected $want, got $got) - the harness-owned file was altered"
    fi
  else
    fail "golden $name is missing from the image"
  fi
done

# ----------------------------------------------------------------- 1. tree ----
echo "== 1. tree provenance =="
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
  echo "ok: upstream fix commit is not present in the clone"
fi

porcelain="$(git -C "$SRC" status --porcelain 2>/dev/null || true)"
bad=""
nmodified=0
if [ -n "$porcelain" ]; then
  while IFS= read -r line; do
    case "$line" in
      " M "*)
        if printf '%s\n' "$line" | grep -Eq "$ALLOWED_MODIFIED"; then
          nmodified=$((nmodified + 1))
        else
          bad="$bad$line
"
        fi
        ;;
      *)
        bad="$bad$line
"
        ;;
    esac
  done <<EOF
$porcelain
EOF
fi
if [ -n "$bad" ]; then
  fail "unexpected working-tree changes (only the cache-removal accounting sources may be modified, and nothing may be added):"
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
fi
if [ "$nmodified" -eq 0 ]; then
  fail "no tracked source file was modified - the deliverable /app/src is unchanged"
else
  echo "ok: $nmodified accounting source file(s) modified"
fi

# ---------------------------------------------------------------- 2. build ---
echo "== 2. build the project (offline) =="
if ( cd "$SRC" && CARGO_NET_OFFLINE=true timeout 1500 cargo build -p uv ) > /tmp/build.out 2>&1; then
  echo "ok: cargo build -p uv"
elif [ -x "$UV_BIN" ]; then
  echo "note: cargo build failed, but a pre-existing binary is present; continuing to surface test failures" >&2
  tail -20 /tmp/build.out | sed 's/^/    /' >&2
  fail "cargo build -p uv failed to compile the repaired tree"
else
  tail -20 /tmp/build.out | sed 's/^/    /' >&2
  fail "cargo build -p uv failed and no binary exists"
fi

if [ ! -x "$UV_BIN" ]; then
  fail "no uv binary at $UV_BIN"
fi

# ------------------------------------------------- 3. golden test + suites ---
echo "== 3. upstream regression test for this bug (crate level) =="
golden_ok=0
mkdir -p "$SRC/crates/uv-cache/tests"
trap 'rm -rf "$SRC/crates/uv-cache/tests"; [ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
for variant in removal.rs removal_legacy_api.rs; do
  cp "$GOLDEN_DIR/$variant" "$SRC/crates/uv-cache/tests/removal.rs"
  if ( cd "$SRC" && CARGO_NET_OFFLINE=true timeout 900 cargo test -p uv-cache --test removal -q ) > /tmp/golden.out 2>&1; then
    echo "ok: golden regression test passed (variant $variant)"
    golden_ok=1
    break
  fi
  echo "note: golden variant $variant did not pass: $(tail -1 /tmp/golden.out)" >&2
  sed -n 's/^test result: .*/&/p' /tmp/golden.out | tail -1 >&2
done
if [ "$golden_ok" -ne 1 ]; then
  fail "the upstream cache-removal regression test (removal.rs, 4 cases) does not pass against the repaired tree (tried both upstream and legacy API naming)"
fi

echo "== 4. the project's own existing crate suites =="
if ( cd "$SRC" && CARGO_NET_OFFLINE=true timeout 900 cargo test -p uv-cache -q ) > /tmp/suite1.out 2>&1; then
  echo "ok: cargo test -p uv-cache"
else
  tail -30 /tmp/suite1.out | sed 's/^/    /' >&2
  fail "cargo test -p uv-cache is not fully green"
fi
if ( cd "$SRC" && CARGO_NET_OFFLINE=true timeout 900 cargo test -p uv-fs -q ) > /tmp/suite2.out 2>&1; then
  echo "ok: cargo test -p uv-fs"
else
  tail -30 /tmp/suite2.out | sed 's/^/    /' >&2
  fail "cargo test -p uv-fs is not fully green"
fi
rm -rf "$SRC/crates/uv-cache/tests"
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

# -------------------------------------------------------------- 5. hidden -----
echo "== 5. hidden end-to-end cases =="
n_hidden=0
for case in /tests/hidden/case*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name="$(basename "$case")"
  if bash "$case/run.sh" > "/tmp/hidden-$name.out" 2>&1; then
    echo "ok: hidden case $name"
  else
    echo "FAIL: hidden case $name" >&2
    tail -20 "/tmp/hidden-$name.out" | sed 's/^/    /' >&2
    reward=0
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

echo
echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0