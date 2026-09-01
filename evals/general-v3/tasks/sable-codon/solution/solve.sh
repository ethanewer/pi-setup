#!/bin/bash
# Oracle for sable-codon: install the primer-designer deliverable into /app,
# then RUN it on the visible scene to produce /app/primers.json. Never
# reads /tests.
set -eu

cp /solution/design.py /app/design.py
chmod +x /app/design.py

python3 /app/design.py --scene /app/scene.json --out /app/primers.json

echo "solve.sh done -> /app/design.py and /app/primers.json"
ls -l /app/design.py /app/primers.json
