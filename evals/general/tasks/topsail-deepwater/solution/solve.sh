#!/bin/bash
# Oracle for topsail-deepwater: applies the minimal upstream fix for the
# promtool TSDB dump sample-dropping bug to the checkout at /app/src, writes
# the /app/repro.sh deliverable from the authored reproduction template, and
# proves both directions with the project's own test runner.
set -e

SRC=/app/src

# 1. the source fix (the exact upstream change, applied as a patch)
git -C "$SRC" apply /solution/fix-tsdb.patch

# 2. the authored reproduction deliverable
cp /solution/repro-template.sh /app/repro.sh
chmod +x /app/repro.sh

# 3. prove the repaired direction with the project's own runner
echo "== repaired tree: authored repro must pass =="
bash /app/repro.sh

# 4. prove the fixed tree also passes the project's own regression test for
#    this bug (extracted upstream test, harness-owned)
cd "$SRC"
cp /opt/golden/tsdb_test.go cmd/promtool/tsdb_test.go
go test -v ./cmd/promtool -run TestTSDBDumpNativeHistogram
go test -v ./cmd/promtool -run TestFormatSeriesSetRejectsUnknownSampleType
git checkout -- cmd/promtool/tsdb_test.go

echo "ORACLE OK"