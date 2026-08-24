#!/bin/bash
set -euo pipefail

cd /app/repo
# Resolve the conflicting config.txt to the required value and complete the merge commit.
{
  # Git merge conflict will have both sections marked. Replace file with required content.
  printf 'resolution=durable\n' > config.txt
  git add config.txt
  git commit -m "resolve conflict: use duplicate resolution"
}