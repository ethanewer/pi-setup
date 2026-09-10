#!/usr/bin/env bash
# Verifier for bracket-harbor (executes-deliverable).
#
# Executes the repaired repository at /app/bh: runs the go toolchain
# (build, vet, test), places two hidden contract-test fixtures into the
# tree and re-runs the suite, checks the deliverables (/app/bh/, /app/fix.md)
# and the fixture invariants (go 1.22 pin, real git history, 5000+ LOC,
# 8-12 packages, untouched test seams). Reward is 1 only when everything is
# green in both the delivered tree and the hidden-augmented trees.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

REPO=/app/bh/
export GOCACHE=/tmp/v-gocache GOPATH=/tmp/v-gopath GOMODCACHE=/tmp/v-gopath/pkg/mod
export GOTOOLCHAIN=local GOPROXY=off

FAILED=0
fail() { echo "FAIL: $*" >&2; FAILED=1; }

# ---------------------------------------------------------------- deliverables
if [ ! -d "$REPO/.git" ]; then
  fail "/app/bh is not a git repository"
fi
if [ ! -f /app/fix.md ]; then
  fail "deliverable /app/fix.md missing"
else
  bytes=$(wc -c < /app/fix.md 2>/dev/null | tr -d ' ')
  if [ -z "$bytes" ] || [ "$bytes" -lt 160 ]; then
    fail "/app/fix.md is too short to be a real write-up ($bytes bytes)"
  fi
fi

# ---------------------------------------------------------------- invariants
if ! grep -q '^go 1\.22' "$REPO/go.mod" 2>/dev/null; then
  fail "go.mod is not pinned to go 1.22"
fi
cc=$(cd "$REPO" && git rev-list --count HEAD 2>/dev/null || echo 0)
if [ "$cc" -lt 10 ]; then
  fail "git history suspiciously shallow: $cc commits"
fi
goloc=$(find "$REPO" -name '*.go' -not -path '*/.git/*' -print0 | xargs -0 wc -l 2>/dev/null | tail -1 | awk '{print $1}')
if [ -z "$goloc" ] || [ "$goloc" -lt 5000 ]; then
  fail "go source LOC = ${goloc:-0}, below the 5000 floor"
fi
npkgs=$(find "$REPO" -name '*.go' -not -path '*/.git/*' -printf '%h\n' | sort -u | wc -l)
if [ "$npkgs" -lt 8 ] || [ "$npkgs" -gt 12 ]; then
  fail "package directories = $npkgs, outside the 8..12 range"
fi

# ------------------------------------------------- fixture seams untouched
# The failing test file and the token vocabulary test are the spec: the fix
# belongs in library code, never in the tests.
if ! cmp -s "$REPO/internal/query/query_test.go" /tests/pristine/query_test.go; then
  fail "internal/query/query_test.go was modified, renamed or removed (tests are the spec; fix the library)"
fi
if ! cmp -s "$REPO/internal/token/token_test.go" /tests/pristine/token_test.go; then
  fail "internal/token/token_test.go was modified, renamed or removed"
fi

# ------------------------------------------------- toolchain on delivered tree
toolchain() { # label
  local label=$1
  local buildlog=/tmp/bh-build-$label.log
  local vetlog=/tmp/bh-vet-$label.log
  local testlog=/tmp/bh-test-$label.log
  rm -f "$buildlog" "$vetlog" "$testlog"
  if ! ( cd "$REPO" && go build ./... >"$buildlog" 2>&1 ); then
    fail "$label: go build ./... failed"; tail -6 "$buildlog" >&2
  fi
  if ! ( cd "$REPO" && go vet ./... >"$vetlog" 2>&1 ); then
    fail "$label: go vet ./... failed"; tail -6 "$vetlog" >&2
  fi
  if ! ( cd "$REPO" && go test ./... >"$testlog" 2>&1 ); then
    fail "$label: go test ./... failed"; tail -15 "$testlog" >&2
  fi
}

toolchain none

# The previously-failing grouping test must have run and passed explicitly.
if ! ( cd "$REPO" && go test ./internal/query/ -run 'TestConditionGrouping' -v >/tmp/bh-qgroup.log 2>&1 ); then
  fail "TestConditionGrouping does not pass"
else
  if ! grep -q -- '--- PASS: TestConditionGrouping' /tmp/bh-qgroup.log; then
    fail "TestConditionGrouping did not report PASS"
  fi
fi

# ------------------------------------------------------- hidden fixtures
hidden=/tests/hidden
for case in h1 h2; do
  if [ ! -d "$hidden/$case" ]; then
    fail "hidden case $case missing"
    continue
  fi
  cp -r "$hidden/$case/." "$REPO/"
  if ! ( cd "$REPO" && go build ./... >/tmp/bh-build-$case.log 2>&1 ); then
    fail "hidden $case: go build ./... failed"; tail -6 /tmp/bh-build-$case.log >&2
  fi
  if ! ( cd "$REPO" && go vet ./... >/tmp/bh-vet-$case.log 2>&1 ); then
    fail "hidden $case: go vet ./... failed"; tail -6 /tmp/bh-vet-$case.log >&2
  fi
  if ! ( cd "$REPO" && go test ./... >/tmp/bh-test-$case.log 2>&1 ); then
    fail "hidden $case: go test ./... failed"; tail -15 /tmp/bh-test-$case.log >&2
  fi
done

# ------------------------------------------------------------- verdict
if [ "$FAILED" = 1 ]; then
  echo "VERDICT: FAIL" >&2
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi
echo "VERDICT: PASS (build, vet, test + hidden h1, h2 all green)" >&2
echo 1 > /logs/verifier/reward.txt
exit 0