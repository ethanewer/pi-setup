#!/bin/bash
# Oracle for juniper-bridge. Copies the solver and runs it on the shipped
# scenario, writing /app/answer.json and the render rasters. Does real work;
# never reads /tests and never cats a precomputed answer.
set -eu

cp /solution/solve.py /app/solve.py
cp /solution/fit.py /app/fit.py
chmod +x /app/solve.py

python3 /app/solve.py /app/scenario /app

echo "oracle produced /app/answer.json"