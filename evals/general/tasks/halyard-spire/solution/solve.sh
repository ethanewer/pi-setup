#!/bin/bash
# Oracle for halyard-spire. Generates the four deliverables into /app by
# running the real solver. The solver does the actual work: it reads the
# shipped application's public interface and the task's wire-format contract,
# and writes a working exporter, a scrape config, recording rules, and the
# PromQL answers. It never reads /tests.
set -eu

python3 /solution/solver.py

echo "oracle wrote /app/exporter.py /app/prometheus.yml /app/rules.yml /app/answers.json"