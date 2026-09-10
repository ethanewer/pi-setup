#!/bin/bash
# Oracle for turret-moor: install the analysis program and run it on the
# visible fixture, producing both declared deliverables.
set -e
cp /solution/analyze.py /app/analyze.py
python3 /app/analyze.py /app/data/sim /app/answer.json