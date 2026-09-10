#!/bin/bash
# Oracle for tenon-orbit: a competent agent's solution to the quantum-dynamics
# task. It ships the real solver to /app and runs it once on a sample parameter
# set to prove the deliverable executes and is numerically sensible. It NEVER
# reads /tests.
set -euo pipefail

cp /solution/solver.py /app/quantum_dynamics.py
chmod +x /app/quantum_dynamics.py

# Prove the deliverable runs and imports the installed QuTiP end to end.
python3 /app/quantum_dynamics.py 1.5 0.8 20.3 > /tmp/oracle_sample.out
python3 - <<'PY'
import math
val = float(open("/tmp/oracle_sample.out").read().strip())
delta, omega, T = 1.5, 0.8, 20.3
W = math.sqrt(delta*delta + omega*omega)
want = (omega*omega / (W*W)) * math.sin(W*T/2.0)**2
assert abs(val - want) < 2e-4, (val, want)
print("oracle self-check: P1(%f)=%.10f want %.10f" % (T, val, want))
PY

echo "tenon-orbit oracle done"
