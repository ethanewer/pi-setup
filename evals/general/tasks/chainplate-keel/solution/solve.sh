#!/bin/bash
# Oracle for chainplate-keel: applies the minimal upstream fix to the
# syncthing checkout at /app/src (split the non-file size consistency check so
# that directories may carry the synthetic directory size), then rebuilds and
# runs the project's own regression case against the repaired tree.
set -e

python3 /solution/fix_protocol_consistency.py /app/src/lib/protocol/protocol.go

echo "== running the project's regression case =="
cd /app/src && go test ./lib/protocol/ -run TestCheckConsistency -v