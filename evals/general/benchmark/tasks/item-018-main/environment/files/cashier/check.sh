#!/bin/bash
# Evaluator for the ledger pool task.
# Builds both modes and runs them side by side on a case file (default cases.txt).
# Prints each run's stdout and exit code so DEBUG vs RELEASE can be compared.
set -u
cd "$(dirname "$0")"
make -s debug release >/dev/null
CASE="${1:-cases.txt}"
echo "== debug  (input: $CASE) =="
./build/debug/cashier --input "$CASE"
echo "debug exit=$?"
echo "== release (input: $CASE) =="
./build/release/cashier --input "$CASE"
echo "release exit=$?"