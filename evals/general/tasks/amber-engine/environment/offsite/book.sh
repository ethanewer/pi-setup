#!/bin/bash
# Submit an offsite plan JSON file to the coordinator booking desk.
# Usage: book.sh [plan.json]   (default: /app/offsite_plan.json)
set -u
PLAN="${1:-/app/offsite_plan.json}"
if [ ! -f "$PLAN" ]; then
  echo "book.sh: no plan file at $PLAN" >&2
  exit 1
fi
resp=$(curl -s -m 15 -X POST "http://127.0.0.1:8701/book" \
        -H 'Content-Type: application/json' --data-binary @"$PLAN") \
  || { echo "book.sh: booking desk did not answer (is the stack up?)" >&2; exit 1; }
printf '%s\n' "$resp" | python3 -m json.tool 2>/dev/null || printf '%s\n' "$resp"
