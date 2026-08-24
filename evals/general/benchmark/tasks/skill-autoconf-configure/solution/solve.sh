#!/bin/bash
set -euo pipefail
cd /app/pkg
./configure --with-feature=blas --enable-opt=64
echo "configured:"
cat defs.h