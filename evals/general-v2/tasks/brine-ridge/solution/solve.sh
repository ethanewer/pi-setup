#!/bin/bash
# Oracle for brine-ridge: configure the saltern framework with the GPU/CUDA
# path explicitly disabled, build the saltern_cpu target, and run the visible
# training job. Never reads /tests.
set -eu

SRC=/app/saltern
BUILD=/app/saltern/build

# ---- 1. Configure with the CUDA path disabled (required on this CPU-only host).
cmake -S "$SRC" -B "$BUILD" -DUSE_GPU=OFF

# ---- 2. Build the CPU training binary.
cmake --build "$BUILD" --target saltern_cpu

test -x /app/saltern/build/saltern_cpu

# ---- 3. Run the visible training job.
"$BUILD/saltern_cpu" --data /app/data/train.csv --epochs 200 --lr 0.5 \
    --out /app/model.json > /app/train-log.txt

echo "solve.sh done"
ls -l "$BUILD/saltern_cpu" /app/model.json /app/train-log.txt
tail -1 /app/train-log.txt
