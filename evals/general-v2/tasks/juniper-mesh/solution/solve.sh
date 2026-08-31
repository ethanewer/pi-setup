#!/bin/bash
# Oracle for juniper-mesh: install the reference solver and RUN it on the
# visible fixtures to produce /app/edges.csv, /app/fit.json, /app/synthetic.csv.
# Never reads /tests.
set -eu

cp /solution/bnfit_ref.py /app/bnfit.py
chmod +x /app/bnfit.py

python3 /app/bnfit.py /app/sensors.csv /app/network.json /app

echo "solve.sh done"
ls -l /app/bnfit.py /app/edges.csv /app/fit.json /app/synthetic.csv
