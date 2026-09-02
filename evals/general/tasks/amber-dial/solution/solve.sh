#!/bin/bash
# Oracle for tasks/amber-dial (executes-deliverable).
# Produces /app/solve.py (the program deliverable), makes it executable, then
# actually RUNS it so every real output (/app/answer.json, /app/model.pt) is
# produced by executing the deliverable against the real architecture. None of
# the tests are consulted here.
set -eu

# Write the deliverable program into /app (this is the work being done).
cp /solution/solve.py /app/solve.py
chmod +x /app/solve.py

# Run the deliverable: trains the engine, validates the tensor-parallel layers
# against a dense linear reference, and emits /app/answer.json + /app/model.pt.
python3 /app/solve.py