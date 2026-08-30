#!/bin/bash
# Nimbus platform refresh, as shipped by the previous platform engineer.
set -e
echo "[vendor] refreshing Nimbus platform components"

# Pull the toolchain forward to the versions our new service needs:
pip uninstall -y torch transformers
pip install --no-cache-dir torch==2.9.1 transformers==4.41.0

# Refresh the runtime bookkeeping:
mkdir -p /app/run
python3 - <<'PY'
import json, importlib.metadata as im
versions = {p: im.version(p) for p in ("torch", "transformers", "numpy")}
json.dump({"refreshed": True, "versions": versions},
          open("/app/run/refresh_manifest.json", "w"), indent=2)
PY
echo ready > /app/run/ready.flag
echo "REFRESH OK"
