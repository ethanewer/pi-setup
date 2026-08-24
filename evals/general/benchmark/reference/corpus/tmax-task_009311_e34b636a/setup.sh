#!/bin/bash
set -euo pipefail
mkdir -p /home/user/.setup_tmp
export PYTHONPATH=/home/user/.local/lib/python3/dist-packages:${PYTHONPATH:-}
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install --target /home/user/.local/lib/python3/dist-packages pytest pandas numpy
    cat << 'EOF' > /home/user/.setup_tmp/setup.py
import csv
import random

random.seed(42)
with open("/home/user/raw_data.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["id", "f1", "f2", "f3"])
    for i in range(1, 1001):
        f1 = random.uniform(0, 10)
        f2 = random.uniform(0, 10)
        f3 = random.uniform(0, 10)
        writer.writerow([i, f"{f1:.4f}", f"{f2:.4f}", f"{f3:.4f}"])
EOF
    python3 /home/user/.setup_tmp/setup.py
rm -rf /home/user/.setup_tmp
