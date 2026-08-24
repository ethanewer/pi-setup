#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.txt ] && [ -f /app/workload.py ]; then
python3 - <<'PYEOF'
import subprocess, sys, cProfile, pstats
try:
    subprocess.run([sys.executable, '-m', 'cProfile', '-o', '/tmp/p.prof', '/app/workload.py'],
                   check=True, capture_output=True)
    st = pstats.Stats('/tmp/p.prof')
    best, best_t = None, -1.0
    for (file, line, func), (cc, nc, tt, ct, callers) in st.stats.items():
        if func.startswith('compute_') and tt > best_t:
            best, best_t = func, tt
    got = open('/app/answer.txt').read().strip()
    sys.exit(0 if best is not None and got == best else 1)
except Exception:
    sys.exit(1)
PYEOF
  if [ $? -eq 0 ]; then reward=1; fi
fi
echo "$reward" > /logs/verifier/reward.txt