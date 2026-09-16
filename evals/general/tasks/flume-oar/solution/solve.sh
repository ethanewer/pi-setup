#!/bin/bash
# Oracle for flume-oar.
#
# Installs the fixed cache implementation into the deliverable path and
# smoke-tests it with the grading invocation (without reading /tests).
# The verifier performs the actual grading.
set -eu

cp /solution/fixed_cache.go /app/lib/cache/cache.go

export HOME="${HOME:-/root}"
export GOPATH="${GOPATH:-$HOME/go}"
if ! mkdir -p "$GOPATH" 2>/dev/null; then
    GOPATH=/var/tmp/go-work
    mkdir -p "$GOPATH"
fi

# Smoke: the full suite must build and pass cleanly once.
cd /app
go test -vet=off ./... >/tmp/oracle-smoke.log 2>&1 || {
    echo "oracle smoke test FAILED" >&2
    tail -20 /tmp/oracle-smoke.log >&2
    exit 1
}

echo "oracle: installed fixed /app/lib/cache/cache.go; suite passes"
