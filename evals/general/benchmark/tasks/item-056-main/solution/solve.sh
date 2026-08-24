#!/bin/bash
set -euo pipefail

mkdir -p /app/out

cd /app
if ! python3 -c "import native" 2>/dev/null; then
    python3 setup.py build_ext --inplace
fi
python3 run_bench.py
echo "benchmark done"