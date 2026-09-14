#!/bin/bash
# Hidden case h3: a plain OLS fit re-processed with a fixed scale through
# get_robustcov_results, supplied scale 7.0, 60 rows / 4 regressors.
set -u
export PYTHONPATH=/app/src${PYTHONPATH:+:$PYTHONPATH}
export PYTHONDONTWRITEBYTECODE=1
exec python /tests/hidden/h3-robustcov-scale-7/case.py