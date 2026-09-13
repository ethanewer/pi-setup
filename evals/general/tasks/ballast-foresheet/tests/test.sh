#!/bin/bash
# Verifier for ballast-foresheet: an upstream-clone debugging task on Hugo.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# the default SSRF policy lets a mixed-case scheme on an IP-literal URL
# through, and lets CGNAT/TEST-NET/benchmarking/reserved/documentation and
# NAT64-embedded or IPv4-mapped non-public addresses through the dial-time
# address gate. The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, the golden regression test the
#      image overlays into config/security/ is byte-identical to the upstream
#      version, config/security/securityConfig.go holds a non-empty diff, and
#      nothing else in the repository changed);
#   1. runs the project's own Go test runner on the overlaid upstream
#      regression tests (both must pass);
#   2. compiles and runs the authored hidden cases mounted at /tests/hidden
#      (copied into the package so go test picks them up, under the shared
#      TestHiddenBallast* names) -- mixed-case schemes, other non-public
#      ranges, NAT64/mapped forms and a text-vs-resolved cross-layer check;
#   3. runs the whole config/security suite with no -run filter, which
#      covers the overlaid golden tests, the hidden vectors and the
#      project's own whitelist suite, and requires it fully green.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

export PATH=/usr/local/go/bin:$PATH
SRC=/app/src
PARENT_SHA=5f0d88b8a3652bbee992f4cbba2b018527f16a15
FIX_SHA=24d5e42ffa33eebdf906c495713f0d2bae30c0cb
GOLDEN_SHA=85e6b0f79e2978f3555c2b14c1b4d35b3fbbc1e6f70d719fb21e94b87fd8ec1e
TEST=config/security/securityConfig_test.go
SRCFILE=config/security/securityConfig.go

fail() {  # fail MESSAGE
  echo "FAIL: $1" >&2
  reward=0
}

# ---------- 0a. the go toolchain must be the pinned, untampered one ----------
# The trial runs as root in a container that shares its filesystem with the
# verifier, so an agent could replace /usr/local/go/bin/go with a shim that
# prints "ok" for every `go test` invocation and then hand the verifier a
# trivial non-fix diff. Pin the go1.27.1 binary by content hash (computed from
# the pinned go.dev tarball at build time) and by version string, and refuse to
# run a single test on a toolchain we cannot authenticate. The same check also
# re-asserts the toolchain on every verifier invocation, so a host that has
# been tampered with scores 0 no matter what the working tree looks like.
GO_BIN=/usr/local/go/bin/go
GO_SHA=30969f97169d7f43fe6a085873d75613adc21e30818a8c61d95bd27275df4624
if [ ! -x "$GO_BIN" ]; then
  fail "the go toolchain is missing at $GO_BIN"
elif [ "$(sha256sum "$GO_BIN" | cut -d' ' -f1)" != "$GO_SHA" ]; then
  fail "the go toolchain at $GO_BIN was modified (sha mismatch, want $GO_SHA)"
elif ! "$GO_BIN" version 2>/dev/null | grep -q 'go1\.27\.1'; then
  fail "the go toolchain at $GO_BIN is not go 1.27.1"
else
  echo "ok: go toolchain is the pinned go1.27.1 binary"
fi

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  fail "/app/src is not a git clone"
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)" != "$PARENT_SHA" ]; then
  fail "/app/src HEAD is not the pinned parent commit"
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  fail "the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)"
else
  echo "ok: the upstream fix commit is not present in the clone"
fi

if [ -z "$(git -C "$SRC" diff -- "$SRCFILE" 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: $SRCFILE differs from the pinned commit"
fi

tree_golden=$(sha256sum < "$SRC/$TEST" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_golden" = "$GOLDEN_SHA" ]; then
  echo "ok: $TEST is byte-identical to the upstream regression test"
else
  fail "$TEST was altered (${tree_golden:-missing}, want $GOLDEN_SHA)"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
expected=" M $SRCFILE"$'\n'" M $TEST"
if [ "$porcelain" = "$expected" ]; then
  echo "ok: working tree differs from the pinned commit only in the fix and the overlaid regression test"
else
  fail "unexpected working-tree changes:"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

# ---------- 1. upstream golden regression tests ------------------------------
echo "== upstream golden regression tests =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && "$GO_BIN" test -vet=off ./config/security \
        -run 'TestCheckAllowedHTTPURLHardenedDefaultsIssue14792|TestCheckAllowedHTTPAddress' \
        -count=1 -v > /tmp/golden.out 2>&1 ); then
    echo "ok: golden tests pass"
  else
    fail "golden tests failed"
    grep -E "^--- (PASS|FAIL)|^ok|^FAIL" /tmp/golden.out | head -30 | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 2. hidden authored cases -----------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  for f in "$case"*.go; do
    [ -f "$f" ] || continue
    if ! cp "$f" "$SRC/config/security/"; then
      fail "could not stage hidden case $f"
    else
      echo "ok: staged hidden case $(basename "$f")"
    fi
  done
done
if [ "$n_hidden" -lt 2 ]; then
  fail "fewer than two hidden cases were exercised"
fi

if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && "$GO_BIN" test -vet=off ./config/security \
        -run 'TestHiddenBallast' -count=1 -v > /tmp/hidden.out 2>&1 ); then
    echo "ok: hidden cases pass"
  else
    fail "hidden cases failed"
    grep -E "^--- (PASS|FAIL)|^ok|^FAIL" /tmp/hidden.out | head -30 | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 3. the whole package suite, no -run filter -----------------------
echo "== full config/security suite =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && "$GO_BIN" test -vet=off ./config/security -count=1 > /tmp/full.out 2>&1 ); then
    if grep -q "^ok" /tmp/full.out; then
      echo "ok: full suite: $(grep '^ok' /tmp/full.out | head -1)"
    else
      fail "full suite did not report ok"
    fi
  else
    fail "full config/security test suite is not green"
    tail -20 /tmp/full.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0