#!/bin/bash
# Oracle for drift-quarry: install the fetcher deliverable into /app, then RUN
# it against the live visible store to produce /app/dataset. Never reads
# /tests.
set -eu

cp /solution/fetch_dataset.py /app/fetch_dataset.py
chmod +x /app/fetch_dataset.py

rm -rf /app/dataset
python3 /app/fetch_dataset.py --endpoint http://127.0.0.1:9000 \
    --bucket cirque --out /app/dataset

echo "solve.sh done -> /app/fetch_dataset.py and /app/dataset"
ls -l /app/fetch_dataset.py /app/dataset
