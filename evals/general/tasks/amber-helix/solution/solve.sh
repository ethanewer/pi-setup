#!/bin/bash
# Oracle for tasks/amber-helix (executes-deliverable).
# Creates every Python deliverable in /app by doing the work (it authors the
# modules), then RUNS each deliverable against the /app fixtures so every
# output artifact (/app/filtered_catalog.json, /app/primers.json,
# /app/affinity_report.json) is produced by executing the deliverable code.
# It never reads /tests.
set -eu

cp /solution/load_catalog.py    /app/load_catalog.py
cp /solution/design_primers.py  /app/design_primers.py
cp /solution/train_affinity.py  /app/train_affinity.py

chmod +x /app/load_catalog.py /app/design_primers.py /app/train_affinity.py

# 1) Catalog filter -> /app/filtered_catalog.json
python3 /app/load_catalog.py \
    --catalog /app/catalog.json \
    --names   /app/wanted_names.txt \
    --limit   1000 \
    --out     /app/filtered_catalog.json

# 2) Primer design -> /app/primers.json
python3 /app/design_primers.py \
    --scene /app/mutation_scene.json \
    --out   /app/primers.json

# 3) Affinity model tuning -> /app/affinity_report.json
python3 /app/train_affinity.py \
    --descriptors /app/affinity_descriptors.npy \
    --targets     /app/affinity_measurements.npy \
    --n_seeds     8 \
    --out         /app/affinity_report.json