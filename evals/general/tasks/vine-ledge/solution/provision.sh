#!/bin/bash
#
# vine-ledge / app provision.sh
#
# Reproducible provisioning for the chain-indexing research workspace.
#
# Guarantees:
#   * NEVER touches the platform-pinned torch/transformers toolchain.
#   * Installs a gRPC Python toolchain SYSTEM-WIDE (importable as `grpc`).
#   * Installs a Jupyter notebook server system-wide and runs it on :8899.
#   * Creates two named venvs: /app/venvs/ingest and /app/venvs/serve.
#   * Installs the chain-query helper + a web microframework (Flask) and
#     requests into the serve venv so a service can start.
#   * Launches a persistent background HTTP API on :8123 backed by chainquery.
#   * Writes /app/requirements.lock describing the exact pinned dependency set.
#
# Idempotent: safe to run repeatedly (already-bound ports and existing venvs
# are left alone).
set -euo pipefail

PY=python3

PIN_GRPCIO=1.83.0
PIN_GRPCIO_TOOLS=1.83.0
PIN_PROTOBUF=7.36.0
PIN_NOTEBOOK=7.6.2
PIN_FLASK=3.1.3
PIN_REQUESTS=2.34.2
PIN_CHAINQUERY=1.2.0
# Immutable platform toolchain - must remain untouched (installed bare in the
# base image). NOTE the installed distribution metadata reports 2.13.0 while
# torch.__version__ reports the +cu130 build qualifier.
PIN_TORCH=2.13.0
PIN_TRANSFORMERS=5.16.1

# 1) gRPC toolchain, SYSTEM-WIDE (not just a venv).
$PY -m pip install --no-cache-dir --disable-pip-version-check \
    "grpcio==$PIN_GRPCIO" "grpcio-tools==$PIN_GRPCIO_TOOLS" "protobuf==$PIN_PROTOBUF"

# 2) Jupyter notebook server, SYSTEM-WIDE.
$PY -m pip install --no-cache-dir --disable-pip-version-check "notebook==$PIN_NOTEBOOK"

# 3) Two named venvs (idempotent: keep existing installs).
[ -x /app/venvs/ingest/bin/python ] || $PY -m venv /app/venvs/ingest
[ -x /app/venvs/serve/bin/python ]  || $PY -m venv /app/venvs/serve

# 4) Chain-query stack into the serve venv (importable package + web micro
#    framework + requests client) so the HTTP service can start.
/app/venvs/serve/bin/pip install --no-cache-dir --disable-pip-version-check \
    "flask==$PIN_FLASK" "requests==$PIN_REQUESTS" /app/pkgs/chainquery

# 5) requests into the ingest venv.
/app/venvs/ingest/bin/pip install --no-cache-dir --disable-pip-version-check \
    "requests==$PIN_REQUESTS"

# 6) Write the chain-query HTTP API service.
mkdir -p /app/service
cat > /app/service/app.py <<'PY'
import json
from flask import Flask, jsonify, request

import chainquery

app = Flask(__name__)


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/height")
def height():
    h = request.args.get("hash", "")
    try:
        r = chainquery.lookup(h)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    return jsonify(r)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8123, threaded=False)
PY

# 7) Launch persistent background services (idempotent: skip if port is bound).
if ! (exec 3<>/dev/tcp/127.0.0.1/8123) 2>/dev/null; then
  nohup /app/venvs/serve/bin/python /app/service/app.py >/tmp/serve.log 2>&1 &
  disown 2>/dev/null || true
fi

if ! (exec 3<>/dev/tcp/127.0.0.1/8899) 2>/dev/null; then
  nohup jupyter-notebook --ip 0.0.0.0 --port 8899 --no-browser --allow-root \
      --ServerApp.token='' --ServerApp.password='' --notebook-dir=/app \
      >/tmp/jupyter.log 2>&1 &
  disown 2>/dev/null || true
fi

# 8) Write the exact pinned dependency set.
cat > /app/requirements.lock <<EOF
# vine-ledge pinned dependency set (reproducible workspace)
grpcio==$PIN_GRPCIO
grpcio-tools==$PIN_GRPCIO_TOOLS
protobuf==$PIN_PROTOBUF
notebook==$PIN_NOTEBOOK
flask==$PIN_FLASK
requests==$PIN_REQUESTS
chainquery==$PIN_CHAINQUERY
torch==$PIN_TORCH
transformers==$PIN_TRANSFORMERS
EOF

echo "provision.sh: workspace provisioned"
