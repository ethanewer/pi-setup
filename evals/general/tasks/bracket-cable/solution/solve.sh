#!/bin/bash
# Oracle for bracket-cable: applies the Context.Copy() errors/accepted fix to
# the real gin checkout at /app/src and proves it with the project's own
# regression test (extracted into /opt/golden/ at image build time) and the
# project's existing context test suite.
set -e

export PATH=/usr/local/go/bin:$PATH

python3 /solution/fix_copy.py /app/src/context.go

echo "== probe (must now pass) =="
cp /app/probe_context_copy_test.go /app/src/
(cd /app/src && go test -v github.com/gin-gonic/gin -test.run 'TestProbeContextCopyRecoversAttachedErrors')
rm -f /app/src/probe_context_copy_test.go

echo "== upstream regression test, extracted from the fix commit =="
cp /app/src/context_test.go /tmp/ctx_test.bak
cp /opt/golden/context_test.go /app/src/context_test.go
(cd /app/src && go test -v github.com/gin-gonic/gin \
  -test.run 'TestContextCopy(CopiesErrors|CopiesAccepted|NilErrorsAndAccepted)')
cp /tmp/ctx_test.bak /app/src/context_test.go
rm -f /tmp/ctx_test.bak

echo "== the project's existing context test suite =="
(cd /app/src && go test -v github.com/gin-gonic/gin -test.run 'TestContext')

echo "== done: Copy() preserves Errors and Accepted =="