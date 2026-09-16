#!/usr/bin/env bash
# Oracle for voussoir-wicket. Installs the real cleanup engine at
# /app/cleanup.py and runs it on the visible incident tree /app/data,
# pruning the junk so the tree fits the host's own policy budget while the
# retained areas stay byte-for-byte identical. Does the actual work; never
# reads /tests and never consults a precomputed answer.
set -euo pipefail

cp /solution/cleanup.py /app/cleanup.py
chmod +x /app/cleanup.py

python3 /app/cleanup.py /app/data

echo "oracle: pruned /app/data with /app/cleanup.py"