#!/bin/bash
# Verifier for bracket-gate: an upstream-clone debugging task on
# serde-rs/serde at parent commit bb99b31e (issue #1468: flattened fields
# made internally tagged structs ignore/replace their tag on serialization).
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug
# in the derive code generator so that an internally tagged struct with a
# flattened tagged enum emits the struct's own tag first and the flattened
# value's own tag after it.  The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, every
#      tracked file other than the derive source and the project's own test
#      file is byte-identical to its HEAD blob — a *content* check, so
#      `git update-index --assume-unchanged` / `--skip-worktree` cannot mask
#      tampering — and no new files were left behind);
#   1. checks the harness integrity manifests baked into /opt/harness at image
#      build time: the golden test bytes, the cargo/rustc binaries and the
#      crates.io source extracts under /opt/cargo/registry/src must all match
#      their build-time hashes (a PATH wrapper around cargo, a replaced golden
#      file, or a tampered dependency source is caught here);
#   2. wipes the prebuilt artifacts of the in-repo crates so everything that
#      matters is recompiled inside the verifier from the content-checked
#      sources (a fix compiled only into an artifact, or a tampered matcher
#      rlib, cannot survive this);
#   3. runs the project's own regression test for this bug, extracted at
#      image build time from the fix commit into /opt/golden/;
#   4. runs the whole test_macros binary (the project's own integration
#      suite for the derive macros, including the golden file) proving the
#      fix broke nothing else;
#   5. runs at least two authored hidden cases that exercise the same code
#      path from inputs the upstream test does not use; each hidden file is
#      first required to be a genuine tagged-flatten regression test.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=bb99b31eb0a55393101f9c80cd959b3a739ad70f
FIX_SHA=1d6ef76cfb339df48232b59cc2ce8568fd19660c
GOLDEN=/opt/golden/test_macros.rs
H=/opt/harness
export RUSTUP_TOOLCHAIN=1.88.0 CARGO_NET_OFFLINE=true

cargo_test () {  # cargo_test LABEL OUT -- args...
  label="$1"; out="$2"; shift 2
  if ( cd "$SRC" && cargo test -p serde_test_suite "$@" > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -50 "$out" | sed 's/^/    /' >&2
  reward=0
  return 1
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  echo "FAIL: /app/src is not a git clone" >&2; reward=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit" >&2; reward=0
elif ! git -C "$SRC" cat-file -e "${PARENT_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the pinned parent commit object is not resolvable in the clone (suspicious .git)" >&2; reward=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
fi

# Content-based provenance: every tracked file except the allowed pair must be
# byte-identical to its HEAD blob. `git status` honours index flags
# (assume-unchanged / skip-worktree); hashing the working-tree bytes does not.
bad=0
while read -r mode f; do
  case "$f" in
    serde_derive/src/ser.rs|test_suite/tests/test_macros.rs) continue ;;
  esac
  if [ "$mode" = "120000" ]; then
    want=$(git -C "$SRC" cat-file blob "HEAD:$f" 2>/dev/null) || { echo "FAIL: cannot resolve HEAD:$f" >&2; bad=1; continue; }
    got=$(readlink -- "$SRC/$f" 2>/dev/null) || { echo "FAIL: tracked file deleted: $f" >&2; bad=1; continue; }
    [ "$got" = "$want" ] || { echo "FAIL: tracked file modified outside the allowed set: $f" >&2; bad=1; }
  else
    want=$(git -C "$SRC" rev-parse -q --verify "HEAD:$f" 2>/dev/null) || { echo "FAIL: cannot resolve HEAD:$f" >&2; bad=1; continue; }
    got=$(git -C "$SRC" hash-object -- "$SRC/$f" 2>/dev/null) || { echo "FAIL: tracked file deleted: $f" >&2; bad=1; continue; }
    [ "$got" = "$want" ] || { echo "FAIL: tracked file modified outside the allowed set: $f" >&2; bad=1; }
  fi
done < <(git -C "$SRC" ls-files -s | awk '{print $1, $4}')
if [ "$bad" = 1 ]; then
  echo "FAIL: unexpected working-tree changes (only serde_derive/src/ser.rs and test_suite/tests/test_macros.rs may differ from HEAD)" >&2
  reward=0
fi

new=$(git -C "$SRC" ls-files --others --exclude-standard 2>/dev/null || true)
if [ -n "$new" ]; then
  echo "FAIL: new/untracked files were left in the tree (target/ is gitignored so this is a real addition):" >&2
  printf '%s\n' "$new" | head -5 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- serde_derive/src/ser.rs 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged (no fix was implemented)" >&2
  reward=0
fi

# ---------- 1. harness integrity (build-time manifests, recomputed now) -------
echo "== harness integrity =="
if [ ! -d "$H" ] || [ ! -r "$H/golden.sha256" ] || [ ! -r "$H/toolchain.sha256" ] || [ ! -r "$H/registry-src.sha256" ]; then
  echo "FAIL: harness integrity manifests missing from the image" >&2; reward=0
else
  if { sha256sum "$GOLDEN" | cmp -s - "$H/golden.sha256"; } \
     && [ -s "$GOLDEN" ] \
     && grep -q "test_internally_tagged_struct_with_flattened_field" "$GOLDEN"; then
    echo "ok: golden test is the fix-commit extraction"
  else
    echo "FAIL: /opt/golden/test_macros.rs was re-pointed or tampered with" >&2; reward=0
  fi
  if { sha256sum /opt/cargo/bin/rustup /opt/cargo/config.toml /opt/rustup/toolchains/*/bin/cargo /opt/rustup/toolchains/*/bin/rustc \
         | cmp -s - "$H/toolchain.sha256"; }; then
    echo "ok: cargo/rustc binaries are the pinned toolchain"
  else
    echo "FAIL: cargo or rustc binary was replaced or modified" >&2; reward=0
  fi
  if { (cd /opt/cargo/registry/src && find . -type f -print0 | sort -z | xargs -0 sha256sum) \
         | cmp -s - "$H/registry-src.sha256"; }; then
    echo "ok: crates.io source extracts unmodified"
  else
    echo "FAIL: a crates.io registry source was modified" >&2; reward=0
  fi
fi

# ---------- 2. rebuild the in-repo crates from source inside the verifier -----
echo "== scrub prebuilt artifacts =="
rm -f "$SRC"/target/debug/deps/libserde-*.{rlib,rmeta} \
      "$SRC"/target/debug/deps/libserde_derive-*.{rlib,rmeta,so} \
      "$SRC"/target/debug/deps/libserde_derive_internals-*.{rlib,rmeta} \
      "$SRC"/target/debug/deps/libserde_test-*.{rlib,rmeta}
if ls "$SRC"/target/debug/deps/libserde-*.{rlib,rmeta} \
      "$SRC"/target/debug/deps/libserde_derive-*.{rlib,rmeta,so} \
      "$SRC"/target/debug/deps/libserde_derive_internals-*.{rlib,rmeta} \
      "$SRC"/target/debug/deps/libserde_test-*.{rlib,rmeta} >/dev/null 2>&1; then
  echo "FAIL: serde crate artifacts could not be scrubbed" >&2; reward=0
else
  echo "ok: in-repo crate artifacts scrubbed (fresh rebuild in the verifier)"
fi

# Drop any per-user cargo config an agent may have injected (config files
# under $HOME/.cargo could redirect registry sources; they are not part of
# the pinned image and must not influence the build).
for h in /root /home/*; do
  [ -d "$h/.cargo" ] && rm -f "$h/.cargo/config" "$h/.cargo/config.toml" || true
done

# ---------- 3. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
else
  cp "$GOLDEN" "$SRC/test_suite/tests/test_macros.rs" \
    || { echo "FAIL: cannot install golden test file" >&2; reward=0; }
  cargo_test "golden regression test" /tmp/golden.out \
    --test test_macros -- test_internally_tagged_struct_with_flattened_field \
    || true
fi

# ---------- 4. the project's own full test_macros binary ----------------------
echo "== the project's own full test_macros suite (with the golden file in place) =="
cargo_test "full test_macros suite" /tmp/full.out \
  --test test_macros \
  || true

# ---------- 5. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  src=$(find "$case" -maxdepth 1 -name '*.rs' | head -1)
  [ -n "$src" ] || continue
  name=$(basename "${src%.rs}")
  if ! grep -Fq 'assert_ser_tokens' "$src" || ! grep -Fq 'flatten' "$src" || ! grep -Fq '#[serde(tag' "$src"; then
    echo "FAIL: hidden case $name does not exercise the tagged-flatten serialization path" >&2
    reward=0
    continue
  fi
  n_hidden=$((n_hidden + 1))
  out="/tmp/hidden-${name}.out"
  if cp "$src" "$SRC/test_suite/tests/${name}.rs" \
     && cargo_test "hidden case $name" "$out" --test "$name"; then
    : # ok
  else
    echo "note: hidden case $name failed" >&2
  fi
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0