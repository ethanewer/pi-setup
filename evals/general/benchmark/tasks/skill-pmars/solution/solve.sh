#!/bin/bash
set -euo pipefail
/app/pmars /app/warrior.red 2>/dev/null | sed -n 's/.*(length \([0-9]*\)).*/\1/p' > /app/length.txt
cat /app/length.txt