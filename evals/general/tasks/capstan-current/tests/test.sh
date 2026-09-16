#!/bin/bash
# Verifier for capstan-current: an upstream-clone debugging task on syncthing.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# UPnP control-URL normalization crashes with "index out of range [0] with
# length 0" when a discovered IGD device returns a control URL with an empty
# path component (a bare query string like "?control=..."). The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable, the regression test data the
#      image overlays into lib/upnp/upnp_test.go is byte-identical to the
#      upstream regression test, lib/upnp/upnp.go holds a non-empty diff,
#      and nothing else in the repository changed);
#   1. runs the project's own regression case TestControlURLParsingQueryOnly
#      from the repaired tree via the project's own `go test` runner and
#      requires it to pass;
#   2. runs the whole UPnP package test module (`go test ./lib/upnp/ -v`)
#      and requires every shipped case (including the three pre-existing
#      ones) to pass;
#   3. copies two authored hidden-case test files into lib/upnp/, runs the
#      module with the project's runner, requires every hidden case to pass,
#      and restores the tree to exactly the agent's state.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=119d5e72efcf7d4c003664640ca0db6f472edfa4
FIX_SHA=703b185982e5cdcff26a119bfa932165d60bda19
GOLDEN=/opt/golden/upnp_test.go
GOLDEN_SHA=6403e2fa74874b0068dcade649168b3bfe65f7209462a4a580870a65e5192ad8
UPNP_TEST=lib/upnp/upnp_test.go
UPNP_SRC=lib/upnp/upnp.go

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

if [ -z "$(git -C "$SRC" diff -- "$UPNP_SRC" 2>/dev/null || true)" ]; then
  fail "the deliverable /app/src is unchanged (no fix was implemented)"
else
  echo "ok: lib/upnp/upnp.go differs from the pinned commit"
fi

tree_golden=$(sha256sum < "$SRC/$UPNP_TEST" 2>/dev/null | cut -d' ' -f1)
if [ "$tree_golden" = "$GOLDEN_SHA" ]; then
  echo "ok: lib/upnp/upnp_test.go is byte-identical to the upstream regression test"
else
  fail "lib/upnp/upnp_test.go was altered (${tree_golden:-missing})"
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
expected=" M lib/upnp/upnp.go"$'\n'" M lib/upnp/upnp_test.go"
if [ "$porcelain" = "$expected" ]; then
  echo "ok: working tree differs from the pinned commit only in the fix and the overlaid regression test"
else
  fail "unexpected working-tree changes:"
  printf '%s\n' "$porcelain" | head -10 | sed 's/^/    /' >&2
fi

# ---------- 1. the project's own regression case ------------------------------
echo "== upstream regression case against the repaired tree =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && go test ./lib/upnp/ -run TestControlURLParsingQueryOnly -v > /tmp/golden.out 2>&1 ); then
    rc=0
  else
    rc=1
  fi
  if [ "$rc" = 0 ] && grep -qF "PASS: TestControlURLParsingQueryOnly" /tmp/golden.out; then
    echo "ok: TestControlURLParsingQueryOnly passes"
  else
    fail "TestControlURLParsingQueryOnly did not pass"
    tail -30 /tmp/golden.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
fi

# ---------- 2. the whole UPnP package module ----------------------------------
echo "== the project's own UPnP package test module =="
if [ "$reward" = 1 ]; then
  if ( cd "$SRC" && go test ./lib/upnp/ -v > /tmp/pkg.out 2>&1 ); then
    rc=0
  else
    rc=1
  fi
  ok_pkg=1
  for name in TestExternalIPParsing TestSoapFaultParsing TestControlURLParsing TestControlURLParsingQueryOnly; do
    if grep -qF "PASS: $name" /tmp/pkg.out; then
      echo "ok: package case passes: $name"
    else
      fail "package case did not pass: $name"
      ok_pkg=0
    fi
  done
  if [ "$rc" != 0 ]; then
    fail "go test ./lib/upnp/ exited non-zero ($rc)"
    tail -20 /tmp/pkg.out 2>/dev/null | sed 's/^/    /' >&2 || true
  fi
  if [ "$ok_pkg" = 1 ]; then
    echo "ok: whole UPnP package module passed"
  fi
fi

# ---------- 3. authored hidden cases ------------------------------------------
echo "== hidden cases =="
n_hidden=0
if [ "$reward" = 1 ]; then
  for f in /tests/hidden/*/*.go; do
    [ -f "$f" ] || continue
    n_hidden=$((n_hidden + 1))
    cp "$f" "$SRC/lib/upnp/upnp_hidden_${n_hidden}_test.go"
  done
  if [ "$n_hidden" -lt 2 ]; then
    fail "fewer than two hidden-case files were found in /tests/hidden"
  else
    if ( cd "$SRC" && go test ./lib/upnp/ -run TestHidden -v > /tmp/hidden.out 2>&1 ); then
      rc=0
    else
      rc=1
    fi
    for name in TestHiddenUpnpCaseOne TestHiddenUpnpCaseTwo TestHiddenUpnpCaseThree; do
      if grep -qF "PASS: $name" /tmp/hidden.out; then
        echo "ok: hidden case passes: $name"
      else
        fail "hidden case did not pass: $name"
      fi
    done
    if [ "$rc" != 0 ]; then
      fail "hidden-case run exited non-zero ($rc)"
      tail -25 /tmp/hidden.out 2>/dev/null | sed 's/^/    /' >&2 || true
    fi
    rm -f "$SRC"/lib/upnp/upnp_hidden_*_test.go
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