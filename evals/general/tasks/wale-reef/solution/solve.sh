#!/bin/bash
# Oracle for wale-reef.
#
# Installs the real solver as /app/run.py, RUNS it on the visible warehouse to
# produce /app/output/*, then writes /app/memory_claim.json from the peak RSS
# the solver just reported (with headroom, capped at the verifier's 512 MB
# ceiling limit). This does the actual work; it never reads /tests and never
# consults a precomputed answer.
set -eu

cp /solution/pipeline.py /app/run.py
chmod +x /app/run.py

rm -rf /app/output
mkdir -p /app/output

log=$(mktemp)
python3 /app/run.py /app/warehouse /app/output >"$log" 2>&1
peak_kb=$(grep -oE 'PEAK_RSS_KB=[0-9]+' "$log" | head -1 | cut -d= -f2)
if [ -z "$peak_kb" ]; then
  echo "oracle: solver did not report a peak RSS" >&2
  tail -30 "$log" >&2
  rm -f "$log"
  exit 1
fi
peak_mb=$((peak_kb / 1024))
declare=$((peak_mb + 96))
if [ "$declare" -gt 512 ]; then declare=512; fi
if [ "$declare" -lt 128 ]; then declare=128; fi
printf '{"ceiling_mb": %d}\n' "$declare" > /app/memory_claim.json
rm -f "$log"

for f in /app/output/daily_summary.csv /app/output/daily_summary.parquet \
         /app/output/report.json /app/memory_claim.json; do
  [ -f "$f" ] || { echo "oracle: $f missing" >&2; exit 1; }
done

echo "oracle produced /app/run.py, /app/output/*, /app/memory_claim.json"
echo "declared ceiling_mb=$declare (measured peak ${peak_kb} KB)"