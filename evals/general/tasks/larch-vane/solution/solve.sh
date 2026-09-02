#!/bin/bash
# Oracle for larch-vane: restore executable bits on the shipped pipeline
# (contents untouched), run the chain on the visible recordings to produce
# the report deliverable, and leave the tree listing untouched.
# Never reads /tests.
set -eu

chmod 0755 /app/pipeline/ingest.sh /app/pipeline/enrich.sh /app/pipeline/publish.sh

# Verify we did not alter script contents (compare against pristine copies).
for f in ingest.sh enrich.sh publish.sh; do
  cmp -s "/app/pipeline/$f" "/opt/pristine/$f" || {
    echo "oracle: pipeline script $f bytes changed unexpectedly" >&2
    exit 1
  }
done

/app/pipeline/publish.sh /app/recordings /app/deployment-report.json

echo "solve.sh done"
ls -l /app/pipeline/ /app/deployment-report.json
cat /app/deployment-report.json
