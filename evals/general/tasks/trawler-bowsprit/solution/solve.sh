#!/bin/bash
# Oracle for trawler-bowsprit: applies the minimal upstream fix to the
# setuptools checkout at /app/src (embed the declared version verbatim in
# Distribution.get_fullname instead of routing it through
# canonicalize_version), writes the canonical reproducing deliverable at
# /app/reproduce.py, and proves the repaired tree behaves correctly.
set -e

python3 /solution/fix_core_metadata.py /app/src/setuptools/_core_metadata.py

cp /solution/reproduce.py /app/reproduce.py
chmod +x /app/reproduce.py

echo "== running the reproduction against the repaired tree =="
python3 /app/reproduce.py

echo "== git status of the deliverable tree =="
git -C /app/src status --short