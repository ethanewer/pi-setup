#!/bin/bash
# Oracle for larch-fathom. Installs the real solver into /app and RUNS it on
# the visible fixtures to produce /app/answer.json, /app/database.env,
# /app/load.sql, /app/clean.sql and /app/generated/* bindings. Does the real
# work; never reads /tests and never cats a precomputed answer.
set -eu

cp /solution/solve.py /app/solve.py
chmod +x /app/solve.py

python3 /app/solve.py \
  /app/data/customers.csv \
  /app/proto/ledger.proto \
  /app/generated \
  /app/answer.json

echo "oracle produced /app/solve.py /app/answer.json /app/generated"