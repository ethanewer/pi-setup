#!/bin/bash
# Verifier for chainplate-keel: an upstream-clone debugging task on syncthing.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the index consistency check rejects a directory entry whose Size equals the
# fixed SyntheticDirectorySize constant (128) that other syncthing versions
# stamp on scanned directories, breaking mixed-version synchronization of
# directory entries. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, the regression test data the
#      image overlays into lib/protocol/protocol_test.go is byte-identical to
#      the upstream regression test, lib/protocol/protocol.go holds a
#      non-empty diff, and nothing else in the repository changed);
#   1. runs the project's own regression case TestCheckConsistency from the
#      repaired tree via the project's own `go test` runner and requires it
#      to pass;
#   2. runs the whole protocol package test module (`go test ./lib/protocol/
#      -v`) and requires every shipped case (including the pre-existing
#      filename, block-size, marshalling, encryption and connection cases) to
#      pass;
#   3. copies two authored hidden-case test files into lib/protocol/, runs
#      the module with the project's runner, requires every hidden case to
#      pass, and restores the tree to exactly the agent's state.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=ee275fee65b37ea75802c8fc3c9decd5a66cb065
FIX_SHA=f1d631d66e1c3101a8968e0713fac29e67329134
GOLDEN=/opt/golden/protocol_test.go
GOLDEN_SHA=ecd37d420e1e22c0bcf0e66666df00baad830c3e0e7b162196893949c0abb517
# sha256 of /usr/local/go/bin/go extracted from the pinned go1.27.1 tarball
# at build time; the verifier runs the project's own `go test`, so a go
# binary that was replaced or wrapped by the agent (printing fake PASS lines)
# must fail the run instead of faking the project's test suite.
GO_BIN_SHA=30969f97169d7f43fe6a085873d75613adc21e30818a8c61d95bd27275df4624
PKG_SRC=lib/protocol/protocol.go
PKG_TEST=lib/protocol/protocol_test.go

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

# The go toolchain shipped in the image must be the one that runs the
# project's test suite; a replaced or wrapped binary could fake every PASS
# line below while the bug stays in place.
echo "== toolchain integrity =="
for b in "$(command -v go 2>/dev/null)" /usr/local/go/bin/go /usr/local/bin/go; do
  if [ -z "$b" ] || [ ! -f "$b" ]; then
    fail "go toolchain binary missing: ${b:-<none>}"
    continue
  fi
  h=$(sha256sum "$b" 2>/dev/null | cut -d' ' -f1)
  if [ "$h" != "$GO_BIN_SHA" ]; then
    fail "the go toolchain binary was replaced or wrapped: $b (sha256 $h, expected $GO_BIN_SHA)"
  fi
done
if [ "$reward" = 1 ]; then
  echo "ok: go toolchain binary is the image's original (sha256 $GO_BIN_SHA)"
fi

if [ -z "$(git -C "$SRC" diff -- "$PKG_SRC" 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: lib/protocol/protocol.go differs from the pinned commit"
fi

tree_golden=$(sha256sum < "$SRC/$PKG_TEST" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_golden" = "$GOLDEN_SHA" ]; then
  echo "ok: lib/protocol/protocol_test.go is byte-identical to the upstream regression test"
else
  fail "lib/protocol/protocol_test.go was altered (${tree_golden:-missing})"
fi

expected=" M lib/protocol/protocol.go"$'\n'" M lib/protocol/protocol_test.go"
porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
if [ "$porcelain" = "$expected" ]; then
  echo "ok: working tree differs from the pinned commit only in the fix and the overlaid regression test"
else
  fail "unexpected working-tree changes:"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

# ---------- 1. the project's own regression case ------------------------------
echo "== upstream regression case against the repaired tree =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && go test ./lib/protocol/ -run TestCheckConsistency -v > /tmp/golden.out 2>&1 ); then
    rc=0
  else
    rc=1
  fi
  if [ "$rc" = 0 ] && grep -qF "PASS: TestCheckConsistency" /tmp/golden.out; then
    echo "ok: TestCheckConsistency passes"
  else
    fail "TestCheckConsistency did not pass"
    tail -30 /tmp/golden.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 2. the whole protocol package module ------------------------------
echo "== the project's own protocol package test module =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && go test ./lib/protocol/ -v > /tmp/pkg.out 2>&1 ); then
    rc=0
  else
    rc=1
  fi
  ok_pkg=1
  for name in TestPing TestClose TestCloseOnBlockingSend TestCloseRace \
              TestClusterConfigFirst TestCloseTimeout TestUnmarshalFDPUv16v17 \
              TestWriteCompressed TestLZ4Compression TestLZ4CompressionUpdate \
              TestCheckFilename TestCheckConsistency TestBlockSize \
              TestClusterConfigAfterClose TestDispatcherToCloseDeadlock \
              TestRequestMaxSize TestRequestZeroSize TestRequestInvalidFilename \
              TestIndexIDString; do
    if grep -qF "PASS: $name" /tmp/pkg.out; then
      echo "ok: package case passes: $name"
    else
      fail "package case did not pass: $name"
      ok_pkg=0
    fi
  done
  if [ "$rc" != 0 ]; then
    fail "go test ./lib/protocol/ exited non-zero ($rc)"
    tail -20 /tmp/pkg.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
  if [ "$ok_pkg" = 1 ]; then
    echo "ok: whole protocol package module passed"
  fi
fi

# ---------- 3. authored hidden cases ------------------------------------------
echo "== hidden cases =="
n_hidden=0
if [ "$reward" = 1 ]; then
  for f in /tests/hidden/*/*.go; do
    [ -f "$f" ] || continue
    n_hidden=$((n_hidden + 1))
    cp "$f" "$SRC/lib/protocol/protocol_hidden_${n_hidden}_test.go"
  done
  if [ "$n_hidden" -lt 2 ]; then
    fail "fewer than two hidden-case files were found in /tests/hidden"
  else
    if ( cd "$SRC" && go test ./lib/protocol/ -run TestHidden -v > /tmp/hidden.out 2>&1 ); then
      rc=0
    else
      rc=1
    fi
    for name in TestHiddenDirSyntheticSizeDeep TestHiddenDirSyntheticDeleted \
                TestHiddenDirJustBelowSynthetic TestHiddenDirLargeSize \
                TestHiddenSymlinkZeroSizeDeep TestHiddenSymlinkOneByte \
                TestHiddenSymlinkJustBelowSynthetic; do
      if grep -qF "PASS: $name" /tmp/hidden.out; then
        echo "ok: hidden case passes: $name"
      else
        fail "hidden case did not pass: $name"
      fi
    done
    if [ "$rc" != 0 ]; then
      fail "hidden-case run exited non-zero ($rc)"
      tail -30 /tmp/hidden.out 2>/dev/null | sed 's/^/    /' >&2 || true
    fi
    rm -f "$SRC"/lib/protocol/protocol_hidden_*_test.go
  fi
fi
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

# ---------- post-hidden tree must be back to the agent's state ----------------
echo "== post-hidden tree state =="
porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
if [ "$porcelain" = "$expected" ]; then
  echo "ok: tree restored after hidden-case runs"
else
  fail "hidden-case teardown left unexpected changes:"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0