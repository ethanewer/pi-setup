#!/bin/bash
# Verifier for flume-quill (executes-deliverable).
# Asserts that /app/flume was upgraded from urfave/cli v1 to the v3 major:
#   - go.mod requires github.com/urfave/cli/v3 (v3.x) and no longer requires
#     the obsolete v1/v2 module
#   - go build ./... and go test ./... pass
#   - two hidden Go test cases that exercise the new API shape pass (staged
#     into the repository and run with go test)
#   - the built binary still drives the CLI end to end
# Writes reward 1 iff every check passes, else 0.
# Guarantee a reward on every exit path.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

REPO=/app/flume
H=/tests/hidden
FAIL=false
failadd(){ echo "FAIL: $1"; FAIL=true; }

if [ ! -d "$REPO" ]; then
  failadd "deliverable /app/flume missing"
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

# ---- 1) go.mod carries the new major ----
if [ ! -f "$REPO/go.mod" ]; then
  failadd "go.mod missing"
else
  if ! grep -q 'github.com/urfave/cli/v3 v3\.' "$REPO/go.mod"; then
    failadd "go.mod does not require github.com/urfave/cli/v3 (v3.x)"
  fi
  if grep -qE 'github\.com/urfave/cli v[12]\.' "$REPO/go.mod"; then
    failadd "go.mod still requires the obsolete cli v1/v2 module"
  fi
fi

# ---- 2) build ----
if ! (cd "$REPO" && go build ./... >/tmp/flume-build.log 2>&1); then
  failadd "go build ./... failed: $(tail -3 /tmp/flume-build.log | tr '\n' ' ')"
fi

# ---- 3) visible tests (must be migrated to the new API) ----
if ! (cd "$REPO" && go test ./... >/tmp/flume-test.log 2>&1); then
  failadd "go test ./... failed: $(tail -3 /tmp/flume-test.log | tr '\n' ' ')"
fi

# ---- 4) hidden case 1: new API shape ----
if ! cp "$H/v3-shape/hidden_v3_test.go" "$REPO/internal/app/hidden_v3_test.go"; then
  failadd "could not stage hidden v3-shape test"
else
  if ! (cd "$REPO" && go test ./... >/tmp/flume-h1.log 2>&1); then
    failadd "hidden v3-shape tests failed: $(tail -3 /tmp/flume-h1.log | tr '\n' ' ')"
  fi
  rm -f "$REPO/internal/app/hidden_v3_test.go"
fi

# ---- 5) hidden case 2: new API shape against a fixture state dir ----
if ! cp "$H/v3-behavior/hidden_behavior_test.go" "$REPO/internal/app/hidden_behavior_test.go"; then
  failadd "could not stage hidden v3-behavior test"
else
  mkdir -p "$REPO/testdata/hidden2"
  if ! cp "$H/v3-behavior/fixture_state/"*.json "$REPO/testdata/hidden2/"; then
    failadd "could not stage hidden v3-behavior fixture"
  fi
  if ! (cd "$REPO" && go test ./... >/tmp/flume-h2.log 2>&1); then
    failadd "hidden v3-behavior tests failed: $(tail -3 /tmp/flume-h2.log | tr '\n' ' ')"
  fi
  rm -f "$REPO/internal/app/hidden_behavior_test.go"
  rm -rf "$REPO/testdata"
fi

# ---- 6) binary smoke test through the new API ----
if (cd "$REPO" && go build -o /tmp/flume-bin ./cmd/flume >/tmp/flume-bin.log 2>&1); then
  SD=$(mktemp -d)
  OUT=$(/tmp/flume-bin --state-dir "$SD" start smoke --input a.csv --output b.json --workers 2 2>&1)
  if ! echo "$OUT" | grep -q 'started run run-'; then
    failadd "binary start failed: $OUT"
  fi
  OUT=$(/tmp/flume-bin --state-dir "$SD" list --json 2>&1)
  if ! echo "$OUT" | grep -q '"pipeline": "smoke"'; then
    failadd "binary list --json failed: $OUT"
  fi
  rm -rf "$SD"
else
  failadd "go build ./cmd/flume failed: $(tail -3 /tmp/flume-bin.log | tr '\n' ' ')"
fi

if [ "$FAIL" = true ]; then
  echo "0" > /logs/verifier/reward.txt
else
  echo "1" > /logs/verifier/reward.txt
fi
exit 0
