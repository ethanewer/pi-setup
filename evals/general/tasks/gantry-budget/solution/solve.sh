#!/bin/bash
# Oracle for gantry-budget: installs the reference batch summariser on the
# deliverable path. The reference summariser does the real work -- reads
# the deployment's records and config, extracts the four judged facts,
# batches requests to fit the deployment's token budget, drives the billed
# model through its ledger -- and the grader then executes the very same
# file. Nothing here reads /tests; the answer is the program itself.
set -eu

cp /solution/solver.py /app/summarizer.py
chmod +x /app/summarizer.py

echo "oracle installed /app/summarizer.py"
ls -l /app/summarizer.py