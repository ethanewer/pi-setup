#!/bin/bash
# Oracle for ember-atlas: install the deliverable, RUN fetch against the live
# visible hub, then RUN verify (offline contract exercised by the verifier).
# Never reads /tests.
set -eu

cp /solution/fetch_model.py /app/fetch_model.py
chmod +x /app/fetch_model.py

rm -rf /app/hf_cache
python3 /app/fetch_model.py fetch --endpoint http://127.0.0.1:8000 \
    --repo-id ridge/topoline-24m --cache /app/hf_cache
python3 /app/fetch_model.py verify --repo-id ridge/topoline-24m \
    --cache /app/hf_cache --prompt "the ridgetop sweep"

echo "solve.sh done -> /app/fetch_model.py and /app/hf_cache"
ls -ld /app/fetch_model.py /app/hf_cache
