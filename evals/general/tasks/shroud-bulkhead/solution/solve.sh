#!/bin/bash
# Oracle for shroud-bulkhead: repairs the pnpm lockfile parser in /app/src
# (working-tree change, no commit), authors the two deliverables, and proves
# the repaired tree end to end with the project's own test harness.
set -euo pipefail

export PATH=/opt/go/bin:$PATH
export CGO_ENABLED=0 GOEXPERIMENT=jsonv2 GOMAXPROCS=1

SRC=/app/src
MOD=pkg/dependency/parser/nodejs/pnpm
P="$SRC/$MOD"

# 1. repair the parser in the working tree (the whole point of the task)
cp /solution/parse.go "$P/parse.go"
cp /solution/types.go "$P/types.go"

# 2. author the deliverables
cp /solution/repro.sh /app/repro.sh
chmod +x /app/repro.sh
cp /solution/repro-fixture.yaml /app/repro-fixture.yaml

# 3. prove: the module's full suite passes on the repaired tree
(
    cd "$SRC"
    go test -v -short "./$MOD/..." > /tmp/oracle-suite.log 2>&1
) || { echo "module suite failed on repaired tree" >&2; tail -30 /tmp/oracle-suite.log >&2; exit 1; }
tail -3 /tmp/oracle-suite.log

# 4. prove: the reproducer fails on the pre-fix tree and passes on the fixed one
rm -rf /tmp/oracle-prefix
cp -a "$SRC" /tmp/oracle-prefix
cp /app/.pristine/pnpm/parse.go "/tmp/oracle-prefix/$MOD/parse.go"
cp /app/.pristine/pnpm/types.go "/tmp/oracle-prefix/$MOD/types.go"
if bash /app/repro.sh /tmp/oracle-prefix > /tmp/oracle-prefix.log 2>&1; then
    echo "reproducer unexpectedly PASSED on the pre-fix tree" >&2
    rm -rf /tmp/oracle-prefix
    exit 1
fi
rm -rf /tmp/oracle-prefix
echo "reproducer fails on the pre-fix tree as required"

bash /app/repro.sh /app/src > /tmp/oracle-fixed.log 2>&1 \
    || { echo "reproducer failed on the repaired tree" >&2; tail -20 /tmp/oracle-fixed.log >&2; exit 1; }
echo "reproducer passes on the repaired tree"

echo "ORACLE_OK"