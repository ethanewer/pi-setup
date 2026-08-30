#!/bin/bash
# dune-notch oracle: install the real parser into /app and RUN it on the
# visible data to produce the visible deliverable. This does the actual
# parsing work; it never reads /tests and never cats a precomputed answer.
set -eu

# 1) Write the parser program (the deliverable the agent must also produce).
cp /solution/parse.py /app/parse.py
chmod +x /app/parse.py

# 2) Run the program on the visible input directory to produce /app/out.tsv.
python3 /app/parse.py /app/data /app/out.tsv

echo "oracle produced /app/parse.py and /app/out.tsv"
