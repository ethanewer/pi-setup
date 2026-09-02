#!/bin/bash
# Oracle for ivory-lantern: install the mirror builder, build the complete
# mirror from the visible upstream tree, and run the shipped offline loader
# against it to capture /app/offline_check.txt. Never reads /tests.
set -euo pipefail

install -m 0755 /solution/build_mirror.py /app/build_mirror.py

python3 /app/build_mirror.py /app/upstream /app/mirror

python3 /app/load_pretrained.py /app/mirror > /app/offline_check.txt
cat /app/offline_check.txt
ls -l /app/mirror /app/offline_check.txt

echo "oracle ok"
