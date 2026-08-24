#!/bin/bash
set -euo pipefail
# (f 5) = 5 * (f 4) = ... = 5*4*3*2*1 = 120
echo -n "120" > /app/answer.txt
echo "wrote /app/answer.txt"