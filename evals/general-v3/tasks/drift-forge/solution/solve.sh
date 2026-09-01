#!/usr/bin/env bash
# Ridgeline drift-sync: author the four tools into /app and produce artifacts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1) Ship the four tools into /app (the real programs, work done when run later).
cp "$SCRIPT_DIR"/normalize_lf.py /app/
cp "$SCRIPT_DIR"/reshard.py        /app/
cp "$SCRIPT_DIR"/order_and_hash.py /app/
cp "$SCRIPT_DIR"/parse_fw.py       /app/
chmod +x /app/normalize_lf.py /app/reshard.py /app/order_and_hash.py /app/parse_fw.py

# 2) Produce the resharded fixture tree under the byte/item caps.
python3 /app/reshard.py /app/input_tree /app/output_tree 4 2048

# 3) Produce the deterministic manifest from the seed tree.
python3 /app/order_and_hash.py manifest /app/seed_tree /app/manifest.json

echo "drift-forge oracle complete"
ls -la /app