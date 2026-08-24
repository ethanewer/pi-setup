#!/bin/bash
set -euo pipefail

printf "print(sum(map(int,open('/app/numbers.txt').read().strip())))" > /app/one.py

python3 /app/one.py