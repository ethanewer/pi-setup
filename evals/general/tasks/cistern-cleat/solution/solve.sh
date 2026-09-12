#!/bin/bash
# Oracle for cistern-cleat: applies the ClientIP multi-line forwarded-header
# fix to the gin checkout at /app/src and proves it with the reproduction
# probe, the project's own regression tests (extracted to /opt/golden at image
# build time) and gin's own full test suite. The tree is only ever touched by
# the minimal fix plus a transient probe copy that is removed again.
set -e

cd /app/src
export GO111MODULE=on GOMODCACHE=/opt/gomodcache GOCACHE=/opt/gocache

echo "== sanity: the probe fails on the unfixed tree (expected) =="
cp /app/probe_clientip_test.go /app/src/
if go test -v github.com/gin-gonic/gin -test.run TestProbeClientIPMultiLines > /tmp/probe-before.log 2>&1; then
  echo "FATAL: probe passed on the unfixed tree; the bug did not reproduce"
  exit 1
fi
grep -E "expected|actual" /tmp/probe-before.log
rm -f /app/src/probe_clientip_test.go

echo "== apply the fix =="
python3 /solution/fix_context.py /app/src/context.go

echo "== probe output after the fix =="
cp /app/probe_clientip_test.go /app/src/
go test -v github.com/gin-gonic/gin -test.run TestProbeClientIPMultiLines
rm -f /app/src/probe_clientip_test.go

echo "== upstream regression tests, run against a throwaway copy =="
rm -rf /tmp/oracle-run
cp -a /app/src /tmp/oracle-run
cp /opt/golden/context_test.go /tmp/oracle-run/context_test.go
cd /tmp/oracle-run
go test -v github.com/gin-gonic/gin -test.run "TestContextClientIPWith(MultipleHeaders|SingleHeader)"
cd /app/src

echo "== gin's own test suite =="
go test -v github.com/gin-gonic/gin
go test -v github.com/gin-gonic/gin/binding
go test -v github.com/gin-gonic/gin/render

echo "== final tree state (must show only context.go modified) =="
git status --porcelain