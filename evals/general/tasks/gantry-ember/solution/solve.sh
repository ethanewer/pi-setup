#!/bin/bash
#
# gantry-ember oracle.  From a pristine container it finds the flaky
# component the same way an agent would (the rotation wheel's winner is
# not reproducible across processes) and fixes the deliverable for real:
#
#   1. replaces the rotation wheel implementation in /app/dutywheel with
#      the deterministic build: the previous on-call member is excluded
#      from the pool and the tie-break key no longer depends on the
#      interpreter's per-process random hash() of the member id;
#   2. smoke-tests the repair by running the full suite five times, each
#      under a different PYTHONHASHSEED, and requires every run green.
#
# The tests themselves are the frozen, unmodified shipped ones; this does
# the actual source fix.  Never reads /tests.
set -euo pipefail

# ---- 1. apply the real fix: deterministic rotation wheel ---------------
cp /solution/rotation_fixed.py /app/dutywheel/dutywheel/rotation.py
chmod 0644 /app/dutywheel/dutywheel/rotation.py

# ---- 2. smoke test: suite must be green under a spread of hash seeds ----
cd /app/dutywheel
for seed in 7 2718 90210 123456789 429496729; do
  if ! out=$(PYTHONHASHSEED="$seed" python3 -m pytest -q -p no:cacheprovider 2>&1); then
    echo "oracle smoke failed under PYTHONHASHSEED=$seed:" >&2
    echo "$out" | tail -20 >&2
    exit 1
  fi
  echo "smoke seed $seed: $(echo "$out" | grep -oE '[0-9]+ passed' | head -1)"
done

echo "oracle done: /app/dutywheel rotation wheel is deterministic and green"