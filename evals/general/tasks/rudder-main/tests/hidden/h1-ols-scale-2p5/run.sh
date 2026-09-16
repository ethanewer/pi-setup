#!/bin/bash
# Hidden case h1: OLS with a user-supplied fixed scale, scale=2.5, 40 rows,
# 3 regressors (independent of the upstream golden test's 50x2 / scale 5.0).
set -u
export PYTHONPATH=/app/src${PYTHONPATH:+:$PYTHONPATH}
export PYTHONDONTWRITEBYTECODE=1
exec python /tests/hidden/h1-ols-scale-2p5/case.py