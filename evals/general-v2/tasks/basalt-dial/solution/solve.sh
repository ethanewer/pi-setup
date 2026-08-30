#!/bin/bash
# Real oracle for basalt-dial: select the tuned configuration (the deliverable)
# and RUN the engine with it on the visible case to produce the report.
# Never reads /tests.
set -eu

mkdir -p /app/config

cat > /app/config/tuning.json <<'JSON'
{
  "method": "rk4",
  "steps": 400,
  "enable_drag": false,
  "drag_coeff": 0.0,
  "softening": 0.0,
  "renormalize": false
}
JSON

python3 /app/engine.py simulate /app/data/case_visible.json \
  /app/config/tuning.json /app/tuning_report.json

echo "solve.sh done -> /app/config/tuning.json and /app/tuning_report.json"
cat /app/tuning_report.json
