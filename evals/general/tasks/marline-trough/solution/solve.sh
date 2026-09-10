#!/bin/bash
# Oracle for marline-trough.
#
# Installs the fixed (streaming, bounded-memory) implementation of the
# fluxline pipeline into /app/fluxline and smoke-runs the deliverable on the
# shipped sample to prove the team's own tests still pass.
#
# The fix preserves the documented transformation semantics exactly; what
# changes is the resource behavior: the transform now streams one record at
# a time with write backpressure instead of buffering the whole input, so
# peak RSS stops growing with the input size, and the entrypoint consumes
# the async generator lazily. The oracle never reads /tests and never
# hardcodes any hidden expectation.
set -eu

cp /solution/pipeline.fixed.js /app/fluxline/lib/pipeline.js
cp /solution/transform.fixed.js /app/fluxline/lib/transform.js

node /app/fluxline/lib/pipeline.js \
  /app/fluxline/data/sample.ndjson \
  /app/fluxline/data/sample.config.json \
  /tmp/oracle-smoke.ndjson

echo "oracle: fixed pipeline installed at /app/fluxline and smoke-run passed"
