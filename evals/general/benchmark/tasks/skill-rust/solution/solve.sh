#!/bin/bash
set -euo pipefail
# Values of i*i for i=1..5: 1+4+9+16+25 = 55
echo -n "55" > /app/answer.txt
echo "wrote /app/answer.txt"