#!/bin/bash
# Oracle for jib-tarn. Does the real work: restores the linear-time hot-path
# module from the last healthy commit (6aeeeb5, "feat: benchmark harness"),
# adds the benchmark regression test, re-runs the correctness suite, produces
# /app/bench.json from the harness, and commits the fix. It never reads
# /tests; it derives everything from the repository itself.
set -eu

cd /app/repo

# The regression is the working-tree state at HEAD.  The last commit that
# still carried the linear implementation is 6aeeeb5; recover that module.
GOOD_SHA=6aeeeb5515db5f7e695f7502731a3d1416475b05
git show "$GOOD_SHA":src/sundial/window.py > src/sundial/window.py

# Add the performance regression test (this IS the benchmark part of the suite).
cp /solution/perf_test.py tests/test_performance.py

python3 -m pytest -q tests

python3 benchmarks/bench.py --repeats 3 --json /app/bench.json

git add -A
git commit -q -m "fix: restore linear-time sliding window; add performance regression test" || true

echo "ORACLE_DONE"
git log --oneline | head -3