#!/bin/bash
set -euo pipefail

# Start pypiserver in the background serving /app/packages on port 8080, no auth.
# (pypiserver >=2 requires the `run` subcommand; `-a . -P .` disables auth and
#  the package directory is a positional argument, not `-P`.)
python3 -m pypiserver run -p 8080 -a . -P . /app/packages &
SERVER_PID=$!

# Wait for the server to become ready (up to ~20s)
ready=0
for _i in $(seq 1 20); do
  if curl -s -o /dev/null "http://localhost:8080/simple/" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
if [ "$ready" != "1" ]; then
  echo "pypiserver did not become ready" >&2
fi

# Install the package from the pypiserver index.
pip install "pipysample" --index-url "http://localhost:8080/simple/" \
  || pip install --no-build-isolation "pipysample" --index-url "http://localhost:8080/simple/"

# Prove the package is importable and behaves correctly.
cat > /app/make_proof.py <<'PYEOF'
import pipysample
with open('/app/proof.txt', 'w') as f:
    f.write(pipysample.greet('world') + ';' + str(pipysample.VALUE + 1) + '\n')
PYEOF
python3 /app/make_proof.py

kill "$SERVER_PID" 2>/dev/null || true
echo "done"