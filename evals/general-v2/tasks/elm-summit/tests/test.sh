#!/usr/bin/env bash
# Verifier for elm-summit.
# Checks the live launch-mode control plane (gRPC gateway on config.port +
# background mlflow on 127.0.0.1:8080) and re-runs /app/serve.py on hidden
# configs/ports. Always ends by writing /logs/verifier/reward.txt.
set -u
set -o pipefail

mkdir -p /logs/verifier

[ -f /app/serve.py ]        || { echo "0" > /logs/verifier/reward.txt; exit 0; }
[ -f /app/atlas_pb2_grpc.py ] || { echo "0" > /logs/verifier/reward.txt; exit 0; }

# Stream the driver's diagnostics to stdout (captured by the harness) and keep
# a persistent copy next to reward.txt so reward-0 runs are auditable.
python3 /tests/driver.py 2>&1 | tee /logs/verifier/driver.log
rc=${PIPESTATUS[0]}

if [ "$rc" -eq 0 ]; then
  echo "1" > /logs/verifier/reward.txt
else
  echo "0" > /logs/verifier/reward.txt
fi