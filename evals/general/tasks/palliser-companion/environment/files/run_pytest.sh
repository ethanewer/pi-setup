#!/bin/bash
# Run the project's own pytest from a neutral location so that `import
# torchvision` resolves to the INSTALLED package (/opt/venv site-packages,
# wired to the /app/src checkout), never to the unbuilt source tree, and the
# repo's test helper package test/ is importable.
#
# Unlike `python3 -m pytest` (which puts the cwd on sys.path and would pick up
# /app/src/torchvision -- a source tree with no compiled extensions), this
# launcher runs the pytest console script from /app/src with PYTHONPATH=test.
#
# Usage: /app/run_pytest.sh [pytest args...]   (run from anywhere)
cd /app/src
export PYTHONPATH=/app/src/test
exec /opt/venv/bin/pytest -p no:cacheprovider "$@"