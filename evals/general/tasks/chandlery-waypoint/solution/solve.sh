#!/bin/bash
# Oracle for chandlery-waypoint: reproduce the missing-$HOME crash and repair
# the real flake8 checkout at /app/src so a home directory that cannot be
# stat'ed is treated the same as a home that is not set, then prove the
# reproduction now exits 0 and the project's config unit tests still pass.
set -e

SRC=/app/src
REPRO=/app/reproduce_unknown_homedir.py
python3 /solution/solver.py "$SRC" "$REPRO"