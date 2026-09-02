#!/bin/bash
# Oracle for zephyr-gasket. Delivers the real working program /app/solve.py,
# makes it executable, and RUNS it to produce /app/answer.json.
set -e
cp /solution/solve.py /app/solve.py
chmod +x /app/solve.py
python3 /app/solve.py
echo "oracle: installed /app/solve.py and produced /app/answer.json"