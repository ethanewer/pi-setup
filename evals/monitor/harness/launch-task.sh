#!/usr/bin/env bash
# Dispatch one benchmark task to the right harness runner. Used by run.sh and
# run-multi.sh so both share a single launch path.
#
# env: TASK RUN_DIR SEED MODEL HARNESS (pi|p|occ|ocdx)
set -euo pipefail
cd "$(dirname "$0")/.."
HARNESS="${HARNESS:-pi}"
case "$HARNESS" in
  pi|p)
    exec bun harness/run-cli.ts
    ;;
  occ|ocdx)
    # The external adapter takes the pi-style MODEL and derives the bare slug.
    export MODEL_LABEL="${MODEL:-openrouter/z-ai/glm-5.3-flash}"
    export MODEL_HANDLE="${MODEL_LABEL#openrouter/}"
    export HARNESS
    exec python3 harness/run-external.py
    ;;
  *)
    echo "launch-task: unknown HARNESS '$HARNESS'" >&2
    exit 2
    ;;
esac
