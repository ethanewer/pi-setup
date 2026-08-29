#!/bin/bash
# iris-terrace oracle: creates the /app deliverables by doing the real work.
#  1. plant the three programs at their literal /app deliverable paths
#  2. run the spectral fitter on the visible /app/spectrum.csv fixture so it
#     produces /app/fit_results.json by fitting (never reading /tests)
#  3. compute the visible stacked-model separability matrix with /app/stack_models.py
#  4. self-check /app/wasserstein.py on the documented example and require the
#     resulting metric value to match sqrt(max(0, P.C)).
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"

cp "$SRC/fit_spectra.py" /app/fit_spectra.py
cp "$SRC/stack_models.py" /app/stack_models.py
cp "$SRC/wasserstein.py" /app/wasserstein.py
chmod +x /app/fit_spectra.py /app/stack_models.py /app/wasserstein.py

# --- 1/2: spectral fitting, produces /app/fit_results.json (a deliverable) ---
python3 /app/fit_spectra.py /app/spectrum.csv --out /app/fit_results.json

# --- 2/2: visible stacked-model separability matrix ---
python3 /app/stack_models.py --out /app/stack_result.json

# --- 3: wasserstein sanity run: distance is the rooted value ---
python3 /app/wasserstein.py --plan <(printf '[[0.3,0.2],[0.2,0.3]]') \
    --cost <(printf '[[1.0,4.0],[4.0,1.0]]') --out /app/wasserstein_check.json
python3 - <<'PY'
import json, math
d = json.load(open('/app/wasserstein_check.json'))['wasserstein']
# sqrt(0.3*1 + 0.2*4 + 0.2*4 + 0.3*1) = sqrt(2.2)
expect = math.sqrt(2.2)
assert abs(d - expect) < 1e-9, ('wasserstein self-check failed', d, expect)
print('wasserstein self-check ok %.6f' % d)
PY

# require the deliverables before declaring success
for f in /app/fit_spectra.py /app/fit_results.json /app/stack_models.py /app/wasserstein.py; do
  [ -f "$f" ] || { echo "solve.sh: missing $f" >&2; exit 1; }
done
echo "iris-terrace oracle complete"
