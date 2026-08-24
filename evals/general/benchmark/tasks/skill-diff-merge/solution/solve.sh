#!/bin/bash
set -euo pipefail
cd /app
git merge-file -p ours.txt base.txt theirs.txt > /app/merged.txt