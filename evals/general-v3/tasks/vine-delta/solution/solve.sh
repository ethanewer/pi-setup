#!/usr/bin/env bash
#
# vine-delta oracle. Produces both deliverables by doing the real work inside a
# pristine container: copies the reference module in, then RUNS it to generate
# /app/moves.txt (the canonical lane replay tape). It never reads /tests.
set -eu
ME=vine-delta

# Author the primary deliverable: the module itself.
cp /solution/solve.py /app/solve.py

# Produce the second deliverable by executing the module (real work, not a cat).
cd /app
python3 /app/solve.py --gen-moves

# Prove every station is functional before finishing.
python3 - <<'PY'
import solve
assert solve.max_quiet_gap([2, 3, 5]) == 1
assert abs(solve.weighted_return([0.5, -1.0, 2.0], [2.0, 3.0, 1.0])) < 1e-9
print("vine-delta oracle self-check passed")
PY

echo "$ME oracle: solve.py in place, moves.txt regenerated"
ls -l /app/solve.py /app/moves.txt