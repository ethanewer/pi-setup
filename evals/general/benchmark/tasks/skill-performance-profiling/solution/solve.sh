#!/bin/bash
set -euo pipefail
python3 -m cProfile -o /tmp/prof.out /app/workload.py
python3 - <<'PYEOF'
import pstats
st = pstats.Stats('/tmp/prof.out')
best, bestt = None, -1.0
for (file, line, func), (cc, nc, tt, ct, callers) in st.stats.items():
    if 'compute_' in func and tt > bestt:
        best, bestt = func, tt
open('/app/answer.txt', 'w').write(best + '\n')
print("slowest function:", best)
PYEOF