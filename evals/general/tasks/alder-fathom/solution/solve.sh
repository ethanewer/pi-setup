#!/bin/bash
# Oracle for alder-fathom: write the deliverable program (an implementation of
# the documented replay protocol), then RUN it on the visible case to produce
# /app/eval_report.json. Never reads /tests.
set -euo pipefail

install -m 0755 /solution/evaluate.py /app/evaluate.py

python3 /app/evaluate.py /app/case /app/eval_report.json

echo "oracle ok"
