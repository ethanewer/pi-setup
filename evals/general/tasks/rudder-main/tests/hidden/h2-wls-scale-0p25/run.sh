#!/bin/bash
# Hidden case h2: WLS with a fixed scale via the "fixed_scale" spelling,
# supplied scale 0.25 (< 1, upstream test only uses 5.0).
set -u
export PYTHONPATH=/app/src${PYTHONPATH:+:$PYTHONPATH}
export PYTHONDONTWRITEBYTECODE=1
exec python /tests/hidden/h2-wls-scale-0p25/case.py