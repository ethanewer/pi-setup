#!/bin/bash
# granite-inlet evaluation runner. With no arguments it produces the visible
# classification + retrieval deliverables; with subcommands it evaluates fresh
# (hidden) datasets.
set -euo pipefail
PY="$(command -v python3)"

if [ "$#" -eq 0 ]; then
  # visible classification deliverable: results/channel_fathom/sprint_07.json
  "$PY" /app/wire_cli.py classify \
    /app/tasks.yaml \
    /app/data/channel_docs.jsonl \
    /app/data/channel_labels.json \
    /app/results/channel_fathom/sprint_07.json
  # retrieval-style deliverable: results/aperture_map/sprint_07.json
  "$PY" /app/wire_cli.py retrieval \
    /app/tasks.yaml \
    /app/data/queries.jsonl \
    /app/results/aperture_map/sprint_07.json
  exit 0
fi

cmd="$1"
case "$cmd" in
  classify)
    "$PY" /app/wire_cli.py classify "$2" "$3" "$4" "$5"
    ;;
  retrieval)
    "$PY" /app/wire_cli.py retrieval "$2" "$3" "$4"
    ;;
  *)
    echo "usage: run_eval.sh [classify <spec> <docs> <labels> <out> | retrieval <spec> <queries> <out>]" >&2
    exit 2
    ;;
esac