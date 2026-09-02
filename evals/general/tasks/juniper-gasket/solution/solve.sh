#!/bin/bash
# juniper-gasket oracle: install the trainer, run it on the visible case to
# produce /app/screen_model.pkl and /app/screen_metrics.json. Never reads /tests.
set -euo pipefail

install -m 0644 /solution/fit_screen.py /app/fit_screen.py
chmod +x /app/fit_screen.py

cd /app
python3 /app/fit_screen.py /app/case /app

for f in /app/fit_screen.py /app/screen_model.pkl /app/screen_metrics.json; do
  [ -f "$f" ] || { echo "oracle missing deliverable $f" >&2; exit 1; }
done

echo "solve.sh done -> /app/fit_screen.py + screener artifacts"
ls -l /app/fit_screen.py /app/screen_model.pkl /app/screen_metrics.json
