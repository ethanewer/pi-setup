#!/bin/bash
# Oracle for ratline-sound: applies the minimal upstream fix to the cobra
# checkout at /app/src (a child flag that shadows a parent persistent flag
# must stay a local flag of the child instead of being dropped and the parent's
# flag shown as inherited), writes the deliverable reproduction, and confirms
# the reproduction plus the full existing suite pass against the repaired tree.
set -e

SRC=/app/src
export PATH=/opt/go/bin:$PATH
export GOMODCACHE=/opt/go/pkg/mod GOCACHE=/opt/go/gocache

mkdir -p /app/repro
cp /solution/repro_test.go /app/repro/repro_test.go
cp /solution/repro_test.go "$SRC/repro_test.go"

patch -p1 -d "$SRC" < /solution/fix.patch

if [ "$(id -u)" = 0 ]; then
  setpriv --reuid=1000 --regid=1000 --clear-groups \
    env HOME=/home/ubuntu PATH=/opt/go/bin:$PATH \
        GOMODCACHE=/opt/go/pkg/mod GOCACHE=/opt/go/gocache \
    sh -c "cd '$SRC' && go test -v ./... -run TestShadowedFlagHelpAndSplit > /tmp/oracle-repro.log 2>&1 && go test -v ./... > /tmp/oracle-full.log 2>&1"
else
  ( cd "$SRC" && go test -v ./... -run TestShadowedFlagHelpAndSplit > /tmp/oracle-repro.log 2>&1 \
      && go test -v ./... > /tmp/oracle-full.log 2>&1 )
fi

rm -f "$SRC/repro_test.go"
test -z "$(git -C "$SRC" status --porcelain | grep -vE '^.. command\.go$' || true)"

echo "== reproduction test =="
grep -cE "PASS:" /tmp/oracle-repro.log | sed 's/^/passing lines: /'
echo "== full suite tail =="
tail -2 /tmp/oracle-full.log