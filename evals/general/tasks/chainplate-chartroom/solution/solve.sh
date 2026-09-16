#!/bin/bash
# Oracle for chainplate-chartroom: applies the minimal upstream fix to the
# poetry checkout at /app/src (substitute falsy but present config values in
# template resolution), then re-runs the regression case and the project's
# own tests/config suite from the repaired tree to prove the fix.
set -e

python3 /solution/fix_config.py /app/src/src/poetry/config/config.py

echo "== golden regression case =="
cd /app/src
/opt/poetry-venv/bin/pytest tests/config/test_config.py \
    -k test_config_process_resolves_falsy_values \
    --no-header -p no:randomly -o addopts=""

echo "== the project's own tests/config suite =="
/opt/poetry-venv/bin/pytest tests/config/ -p no:randomly -o addopts="" -q