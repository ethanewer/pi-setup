#!/bin/bash
# Verifier for bracket-cable: an upstream-clone debugging task on gin-gonic/gin.
#
# The agent must fix, in the real checkout at /app/src, a real upstream bug:
# Context.Copy() drops the Errors and Accepted arrays, so a context snapshot
# looks like a fresh request.  The verifier:
#   0. asserts tree provenance (HEAD is still the pinned parent commit, the
#      upstream fix commit is not reachable from the working clone, remotes
#      untouched, only context.go modified, no scratch files left behind);
#   1. runs the project's own regression test for this bug, extracted at image
#      build time from the fix commit into /opt/golden/ (the golden
#      context_test.go is overlaid on the tree, run, then the checkout's own
#      context_test.go is restored);
#   2. runs the project's own existing context test suite from the tree,
#      proving the fix broke nothing else;
#   3. runs at least two authored hidden cases exercising the same code path
#      from inputs the upstream tests do not use.
#
# Reward is binary and written on every exit path (trap below).

trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier
reward=1

SRC=/app/src
PARENT_SHA=2e4d4f38962a6f15ae496d59b294f307eef95429
FIX_SHA=293ad7edebb3ae30369288bd6416ca0d78474727
GOLDEN=/opt/golden/context_test.go

# Fixtures are harness-owned: the golden regression test is extracted from the
# upstream fix commit at build time, and the hidden cases live on the read-only
# /tests mount. If an agent modified a fixture instead of the source, the
# integrity check below zeroes the reward before the fixture is used.
GOLDEN_SHA256=1d245d37a461375f871b75b202fe9a41c06534744b203d0be5c9a99dceb1201d
HIDDEN_SHA256_copy_rich_errors=83c2fbcd5ca757c107fd441203764690c7e15b0c6b9ba8de856ba61339ec0eef
HIDDEN_SHA256_copy_accepted_original_mutated=3297c47e984b6e4d16c217b9128010b482fff94dc05c98e65898e8e68cfa0085
HIDDEN_SHA256_copy_chain_single_error=ced6d2ab02ce32f3392f0390f18d9f24c763d36bb14f075d4c26ea6a500548f6

expect_sha256 () {  # expect_sha256 PATH EXPECTED_SHA LABEL
  got=$(sha256sum "$1" 2>/dev/null | awk '{print $1}')
  if [ "$got" != "$2" ]; then
    echo "FAIL: $3 has been modified (expected sha256 $2, got ${got:-<missing>}); fixtures are harness-owned, do not touch" >&2
    reward=0
    return 1
  fi
  return 0
}

export PATH=/usr/local/go/bin:$PATH

run_go_test () {  # run_go_test LABEL OUT FILTER
  label="$1"; out="$2"; filter="$3"
  if ( cd "$SRC" && go test -v github.com/gin-gonic/gin -test.run "$filter" > "$out" 2>&1 ); then
    echo "ok: $label"
    return 0
  fi
  echo "FAIL: $label" >&2
  tail -50 "$out" | sed 's/^/    /' >&2
  return 1
}

# ---------- 0. tree provenance -----------------------------------------------
echo "== tree provenance =="
if [ ! -d "$SRC/.git" ]; then
  echo "FAIL: /app/src is not a git clone" >&2; reward=0
elif [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" != "$PARENT_SHA" ]; then
  echo "FAIL: /app/src HEAD is not the pinned parent commit (the tree must be fixed in place, not rewritten)" >&2; reward=0
else
  echo "ok: HEAD is $PARENT_SHA"
fi

if git -C "$SRC" cat-file -e "${FIX_SHA}^{commit}" 2>/dev/null; then
  echo "FAIL: the upstream fix commit is reachable from the working clone (the answer was fetched, not implemented)" >&2
  reward=0
fi

remotes=$(git -C "$SRC" remote 2>/dev/null || true)
if [ "$remotes" != "origin" ]; then
  echo "FAIL: unexpected git remotes: ${remotes:-<none>}" >&2; reward=0
fi

porcelain=$(git -C "$SRC" status --porcelain 2>/dev/null || true)
bad=""
while IFS= read -r line; do
  case "$line" in
    "") ;;
    " M context.go") ;;
    *) bad="${bad}${line}" ;;
  esac
done <<EOF
$porcelain
EOF
if [ -n "$bad" ]; then
  echo "FAIL: unexpected working-tree state (only context.go may be modified, nothing staged, no new files):" >&2
  printf '%s\n' "$bad" | head -10 | sed 's/^/    /' >&2
  reward=0
fi
if [ -z "$(git -C "$SRC" diff -- context.go 2>/dev/null || true)" ]; then
  echo "FAIL: the deliverable /app/src is unchanged: context.go has no modifications (no fix was implemented)" >&2
  reward=0
fi

# ---------- 1. golden: the upstream regression test ---------------------------
echo "== golden test (upstream regression test for this bug) =="
if [ ! -s "$GOLDEN" ]; then
  echo "FAIL: golden test missing from image" >&2; reward=0
elif ! expect_sha256 "$GOLDEN" "$GOLDEN_SHA256" "the golden regression test (/opt/golden/context_test.go)"; then
  :  # reward already zeroed; skip running the tampered fixture
else
  cp "$SRC/context_test.go" /tmp/ctx_test.bak || true
  cp "$GOLDEN" "$SRC/context_test.go"
  run_go_test "golden TestContextCopyCopies{Errors,Accepted,NilErrorsAndAccepted}" \
    /tmp/golden.out 'TestContextCopy(CopiesErrors|CopiesAccepted|NilErrorsAndAccepted)' || reward=0
  cp /tmp/ctx_test.bak "$SRC/context_test.go" 2>/dev/null || true
  rm -f /tmp/ctx_test.bak
fi

# ---------- 2. the project's own existing context suite -----------------------
echo "== the project's own existing context test suite =="
run_go_test "existing TestContext* suite" /tmp/own.out 'TestContext' || reward=0

# ---------- 3. hidden cases ---------------------------------------------------
echo "== hidden cases =="
n_hidden=0
for case in /tests/hidden/*/; do
  [ -d "$case" ] || continue
  n_hidden=$((n_hidden + 1))
  name=$(basename "$case")
  f="$case/context_copy_hidden_test.go"
  if [ ! -s "$f" ]; then
    echo "FAIL: hidden case $name has no context_copy_hidden_test.go" >&2; reward=0
    continue
  fi
  sha_var="HIDDEN_SHA256_${name}"
  if ! expect_sha256 "$f" "${!sha_var:-}" "hidden case $name (/tests/hidden/$name/context_copy_hidden_test.go)"; then
    continue
  fi
  cp "$f" "$SRC/context_copy_hidden_test.go"
  out="/tmp/hidden-${name}.out"
  run_go_test "hidden case $name" "$out" 'TestHiddenCopy' || reward=0
  rm -f "$SRC/context_copy_hidden_test.go"
done
if [ "$n_hidden" -lt 2 ]; then
  echo "FAIL: fewer than two hidden cases were exercised" >&2; reward=0
fi

# ---------- 4. final hygiene: verifier leaves the tree as it found it ---------
leftover=$(git -C "$SRC" status --porcelain 2>/dev/null | grep -v '^ M context.go$' || true)
if [ -n "$leftover" ]; then
  echo "FAIL: verifier cleanup left the working tree dirty:" >&2
  printf '%s\n' "$leftover" | head -10 | sed 's/^/    /' >&2
  reward=0
fi

echo "REWARD=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0