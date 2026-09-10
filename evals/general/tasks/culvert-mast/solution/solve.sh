#!/bin/bash
# Oracle for tasks/culvert-mast. Builds the deliverable binary from the
# reference source and smoke-checks it on the shipped fixture. Never reads
# /tests; it does the real work (compile + run).
set -eu

mkdir -p /app/culvert-src
cp /solution/main.go /app/culvert-src/main.go

export GOCACHE=/tmp/gocache
go build -o /app/culvert /app/culvert-src/main.go

# smoke: the reference implementation must satisfy the visible fixture
/app/culvert check --format table >/dev/null
/app/culvert resolve --format json >/dev/null

echo "oracle built /app/culvert from /app/culvert-src/main.go"