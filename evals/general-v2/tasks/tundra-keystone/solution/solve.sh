#!/usr/bin/env bash
# tundra-keystone oracle: author the three programs, then RUN them to produce
# the default /app artifacts (grad_exchange.npz, async_log.txt).
set -euo pipefail

# 1) author the deliverables (real programs, not precomputed answers)
cp /solution/pipeline_parallel.py /app/pipeline_parallel.py
cp /solution/async_pool.py        /app/async_pool.py
cp /solution/mp_entry.py          /app/mp_entry.py
chmod +x /app/pipeline_parallel.py /app/async_pool.py /app/mp_entry.py

# 2) run the pipeline (default world=4 layers=8 d=16 batch=3) -> grad_exchange.npz
python3 /app/pipeline_parallel.py            # writes /app/grad_exchange.npz

# 3) run the async scheduler (default 6 jobs, cap 3, cancel after 3) -> async_log.txt
python3 /app/async_pool.py                   # writes /app/async_log.txt

# 4) smoke-run the multiprocessing entry (default 4 workers)
python3 /app/mp_entry.py >/tmp/mp_smoke.out 2>&1

echo "solve ok"