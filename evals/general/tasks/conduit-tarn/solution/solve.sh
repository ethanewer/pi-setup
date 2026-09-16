#!/bin/bash
# Oracle for conduit-tarn. Runs the real solver (reproduce -> fix -> regression
# test -> verify -> commit). Never reads /tests.
set -euo pipefail

cd /app/conduit
python3 /solution/fix_regression.py