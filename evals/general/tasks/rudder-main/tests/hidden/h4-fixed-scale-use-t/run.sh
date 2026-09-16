#!/bin/bash
# Hidden case h4: OLS with a fixed scale plus use_t=True, supplied scale 1.5,
# 120 rows (upstream test uses neither use_t nor n=120).
set -u
export PYTHONPATH=/app/src${PYTHONPATH:+:$PYTHONPATH}
export PYTHONDONTWRITEBYTECODE=1
exec python /tests/hidden/h4-fixed-scale-use-t/case.py