#!/bin/bash
set -euo pipefail
total=0
while read -r line; do
  total=$(( total + line ))
done < /app/numbers.txt
echo "$total" > /app/sum_output.txt
echo "wrote $total"