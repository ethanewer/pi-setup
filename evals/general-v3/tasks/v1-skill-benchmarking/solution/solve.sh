#!/bin/bash
set -euo pipefail
cat > /app/bench.py <<'PYEOF'
import time, json, sys
sys.path.insert(0, '/app')
from candidates import impl_a, impl_b
n = 5000000
reps = 10
def bench(fn):
    best = float('inf')
    for _ in range(reps):
        t0 = time.perf_counter()
        fn(n)
        dt = time.perf_counter() - t0
        best = min(best, dt)
    return best
ta = bench(impl_a)
tb = bench(impl_b)
slower = 'A' if ta > tb else ('B' if tb > ta else 'A')
out = {'winner_slower': slower, 'time_a_sec': round(ta, 4), 'time_b_sec': round(tb, 4), 'reps': reps}
json.dump(out, open('/app/bench.json', 'w'), indent=2)
PYEOF
python3 /app/bench.py
