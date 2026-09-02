#!/bin/bash
# Oracle for tasks/prism-atlas (executes-deliverable).
#
# Produces the four working deliverables in /app by writing each program, then
# RUNS that work so every real output is computed rather than precomputed:
#   * /app/rank_callsites.py  -> /app/callsite_rank.txt          (part 1)
#   * /app/stateful_cli.py    -> accumulated state (parts 2 & 3)
#   * /app/out.txt            (part 3, the integer = final state)
#   * /app/apply_macros.vim   -> /app/transformed/*              (part 4)
# Never reads /tests.
set -eu

# 1. Lay down the deliverable programs (this IS the authoring work).
cp /solution/rank_callsites.py  /app/rank_callsites.py
cp /solution/stateful_cli.py    /app/stateful_cli.py
cp /solution/apply_macros.vim   /app/apply_macros.vim
chmod +x /app/rank_callsites.py /app/stateful_cli.py

# 2. Part 1: aggregate + rank the fixture's call-site signatures -> top-10.
python3 /app/rank_callsites.py /app/data/calls /app/callsite_rank.txt 10

# 3. Parts 2 & 3: run the documented transaction sequence with the rolling
#    counter, then emit the computed integer as text.
python3 /app/stateful_cli.py 5
python3 /app/stateful_cli.py 9
python3 /app/stateful_cli.py -2
python3 /app/stateful_cli.py 11
python3 /app/stateful_cli.py 8
python3 /app/stateful_cli.py 14
python3 /app/stateful_cli.py 0
value=$(tr -d '[:space:]' < /app/state/state.txt)
printf '%s\n' "$value" > /app/out.txt

# 4. Part 4: headless vim macro transform of every depot row file.
vim -es -N -u NONE -i NONE -n -S /app/apply_macros.vim \
    /app/data/rows/depot-a.txt /app/data/rows/depot-b.txt \
    /app/data/rows/depot-c.txt /app/data/rows/depot-d.txt </dev/null

# Guard: every declared deliverable output exists after the transform pass.
for f in /app/transformed/depot-a.txt /app/transformed/depot-b.txt \
         /app/transformed/depot-c.txt /app/transformed/depot-d.txt; do
    [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
done


echo "solve.sh finished:"
ls -la /app/callsite_rank.txt /app/out.txt /app/transformed/