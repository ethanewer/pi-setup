#!/bin/bash
set -euo pipefail
cd /app/pkg
make
echo "built:"; cat built/output.txt