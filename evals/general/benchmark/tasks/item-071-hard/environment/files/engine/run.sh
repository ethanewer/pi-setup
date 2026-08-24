#!/bin/bash
export OMP_NUM_THREADS=1
cd /app/engine || exit 1
rm -rf out
mkdir -p out
torchrun --standalone --nnodes=1 --nproc_per_node=2 main.py
