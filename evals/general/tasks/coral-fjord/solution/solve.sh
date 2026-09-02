#!/bin/bash
# coral-fjord oracle: install the FIXED pipeline.py and the trainer, then RUN
# the trainer on the visible case to produce every deliverable in /app.
# Never reads /tests.
set -euo pipefail

install -m 0644 /solution/pipeline.py /app/pipeline.py
install -m 0644 /solution/train_score.py /app/train_score.py

cd /app
python3 /app/train_score.py /app/case /app

# Every declared deliverable must be produced in /app by the run above.
for f in \
  /app/pipeline.py \
  /app/train_score.py \
  /app/model.pt \
  /app/training_report.json
 do
  [ -f "$f" ] || { echo "oracle missing deliverable $f" >&2; exit 1; }
done

echo "solve.sh done -> /app/pipeline.py + trainer + trained artifacts"
ls -l /app/pipeline.py /app/train_score.py /app/model.pt /app/training_report.json
