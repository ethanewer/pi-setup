#!/usr/bin/env bash
# Oracle for jerkin-cleat: write the image pipeline deliverable and build it.
set -euo pipefail
cp /solution/pipeline.c /app/pipeline.c
gcc -O2 -o /app/image_pipeline /app/pipeline.c -lm
echo "oracle: built /app/image_pipeline from /app/pipeline.c"