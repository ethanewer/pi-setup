#!/bin/bash
# Oracle: build CPU-only and capture output.
set -euo pipefail
cd /app/project
# Ensure a CPU-only build configuration (macro not defined).
cat > build_config.h <<'EOF'
/* CPU-only build configuration: CUDA is disabled. */
#ifndef BUILD_CONFIG_H
#define BUILD_CONFIG_H
#endif
EOF
make run
./run > /app/run.txt