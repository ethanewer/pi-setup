#!/bin/bash
set -euo pipefail

cat > /app/benchmarking_answer.txt <<'EOF'
Sound benchmarking repeats the measurement over many runs or iterations so that noisy outliers do not dominate. You then report a summary statistic of the collected runtimes, typically the mean or the median. Measurements should be taken under controlled, reproducible conditions: warm up the system first, keep the machine and software state fixed, and avoid background load.
EOF