#!/bin/bash
# Oracle for brisk-anchor. Authors the four reusable programs into /app (the
# deliverables), makes them executable, then RUNS each one against the shipped
# fixtures so every JSON deliverable is genuinely produced by executing the
# programs. Never reads /tests; never cats a precomputed answer.
set -eu

S=/solution

cp "$S/ocr.py"        /app/ocr.py
cp "$S/field-map.py"  /app/field-map.py
cp "$S/chess-read.py" /app/chess-read.py
cp "$S/extract.py"    /app/extract.py

chmod +x /app/ocr.py /app/field-map.py /app/chess-read.py /app/extract.py

# Run each deliverable -> emits the required /app JSON. Output paths are
# passed explicitly so the deliverable filenames are literal /app paths.
python3 /app/ocr.py /app/scans /app/invoice-labels.json
python3 /app/field-map.py -f /app/fields -c /app/chunks \
    -m /app/field-map.json -s /app/retrieval-stats.json
python3 /app/chess-read.py /app/boards /app/positions.json
python3 /app/extract.py /app/docs /app/profiles.json

# Sanity: the four JSON reports exist and are non-empty.
for f in invoice-labels.json field-map.json retrieval-stats.json positions.json profiles.json; do
    [ -s "/app/$f" ] || { echo "oracle: /app/$f missing/empty" >&2; exit 1; }
done

echo "brisk-anchor oracle OK"