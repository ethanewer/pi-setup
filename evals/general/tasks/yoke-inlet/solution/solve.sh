#!/usr/bin/env bash
# Yoke-inlet oracle: the reference "agent". Writes the three deliverables
# (/app/start.sh, /app/nginx.conf, /app/tls/ca.crt) exactly as a correct agent
# would, then verifies the stack comes up through its own TLS front door.
set -euo pipefail

mkdir -p /app/tls

bash /solution/solver.sh

# sanity check mirroring the verifier: the stack must already be serving
bash /app/start.sh
curl -sS --cacert /app/tls/ca.crt -o /dev/null "https://127.0.0.1:8443/mortar"
echo "oracle: /app/start.sh, /app/nginx.conf, /app/tls/ca.crt in place and serving"