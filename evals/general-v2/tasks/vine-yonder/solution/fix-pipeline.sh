#!/bin/bash
# fix-pipeline.sh -- repair a chained pipeline's dependencies + missing output
# directory so every stage runs in order, then run it.
#
# Usage: bash /app/fix-pipeline.sh [PIPEDIR] [OUTLOG]
#   PIPEDIR  (default /app/pipeline) must contain stage1.py stage2.py stage3.py
#            plus any misplaced helper staged as <name>.py.example
#   OUTLOG   (default /app/pipeline.out) receives the stages' stdout.
#
# The shipped pipeline is broken in two ways that must be fixed here:
#   * a required helper module is present only as a misplaced <name>.py.example
#     (the real module import by the stages is missing), and
#   * the shared `generated/` output directory does not exist.
set -euo pipefail

PIPE="${1:-/app/pipeline}"
OUT="${2:-/app/pipeline.out}"

cd "$PIPE"

# 1) Restore any mis-named helper module (e.g. pipeline_helpers.py.example ->
#    pipeline_helpers.py).  Only copy when the real module is still missing.
for f in ./*.py.example; do
    [ -e "$f" ] || continue
    tgt="${f%.example}"
    [ -f "$tgt" ] || cp "$f" "$tgt"
done

# 2) Ensure the shared output directory exists.
mkdir -p generated

# 3) Run the stages strictly in order and capture their stdout.
{
    python3 stage1.py &&
    python3 stage2.py &&
    python3 stage3.py
} > "$OUT"

echo "pipeline repaired and executed -> $OUT"