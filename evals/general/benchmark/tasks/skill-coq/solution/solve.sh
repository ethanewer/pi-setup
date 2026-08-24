#!/bin/bash
set -euo pipefail

# pow2 2 = 2*(pow2 1) = 2*(2*(pow2 0)) = 2*2*1 = 4 ; succ (pow2 2) = 5
printf '4\n5\n' > /app/answer.txt