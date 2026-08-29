#!/usr/bin/env bash
# Oracle for elm-summit: materialise the /app/serve.py deliverable and bring the
# control plane online so the verifier sees a live gRPC gateway and mlflow.
set -euo pipefail

mkdir -p /app
cp /solution/template/serve.py /app/serve.py
chmod +x /app/serve.py

# Launch mode: mlflow tracking server (127.0.0.1:8080) + gateway on config.port.
nohup python3 /app/serve.py >/app/launch.log 2>&1 &
echo "launched control plane pid $!"
# give the gateway + mlflow a moment to bind before the verifier probes
sleep 6