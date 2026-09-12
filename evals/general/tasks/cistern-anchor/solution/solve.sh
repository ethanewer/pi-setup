#!/bin/bash
# Oracle for cistern-anchor: applies the minimal upstream fix to the cobra
# checkout at /app/src (the subcommand-name search must skip arguments that
# are the value of a preceding flag) and confirms the project's own
# regression test and its full test suite pass against the repaired tree.
set -e

SRC=/app/src
export PATH=/opt/go/bin:$PATH
export GOMODCACHE=/opt/go/pkg/mod GOCACHE=/opt/go/gocache

patch -p1 -d "$SRC" < /solution/command_fix.patch

if [ "$(id -u)" = 0 ]; then
  setpriv --reuid=1000 --regid=1000 --clear-groups \
    env HOME=/home/ubuntu PATH=/opt/go/bin:$PATH \
        GOMODCACHE=/opt/go/pkg/mod GOCACHE=/opt/go/gocache \
    sh -c "cd '$SRC' && go test -v ./... -run TestFind > /tmp/oracle-golden.log 2>&1 && go test -v ./... > /tmp/oracle-full.log 2>&1"
else
  ( cd "$SRC" && go test -v ./... -run TestFind > /tmp/oracle-golden.log 2>&1 \
      && go test -v ./... > /tmp/oracle-full.log 2>&1 )
fi

echo "== regression test (TestFind) =="
grep -cE "PASS:" /tmp/oracle-golden.log | sed 's/^/passing test lines: /'
echo "== full suite tail =="
tail -2 /tmp/oracle-full.log