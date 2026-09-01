#!/bin/bash
# Oracle for tasks/prism-ledge (executes-deliverable).
# Produces /app/pipeline.py, compiles /app/cdecode, then RUNS the pipeline over
# the shipped visible clip so /app/out.csv + /app/analysis.json are produced by
# executing the deliverable (never by reading /tests).
set -eu

# 1. Deliver the program.
cp /solution/pipeline.py /app/pipeline.py
chmod +x /app/pipeline.py

# 2. Build the C raster decoder from its source (the work being done).
cp /solution/cdecode.c /app/cdecode.c
gcc -O2 -o /app/cdecode /app/cdecode.c $(pkg-config --cflags --libs libpng)
chmod +x /app/cdecode

# 3. Run the pipeline over the visible clip => real outputs.
python3 /app/pipeline.py /app/clip_v /app

echo "solve complete"
ls -la /app/out.csv /app/analysis.json /app/cdecode /app/pipeline.py