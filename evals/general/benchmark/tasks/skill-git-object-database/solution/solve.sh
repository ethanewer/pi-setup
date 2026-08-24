#!/bin/bash
set -euo pipefail
h=$(git hash-object /app/repo/seed/input.txt)
printf '%s' "$h" > /app/answer.txt