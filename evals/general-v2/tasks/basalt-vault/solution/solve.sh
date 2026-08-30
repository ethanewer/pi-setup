#!/usr/bin/env bash
# Oracle for basalt-vault: install the real explorer deliverable /app/grid.py,
# start the maze service against the shipped fixture, run the explorer against
# maze-0 to actually walk the maze and write /app/map.txt, then finalize.
set -euo pipefail

install -m 0755 /solution/grid.py /app/grid.py

# start the vault service on the default maze-0 fixture
python3 /app/vault_server.py --port 8123 --fixture /app/vault_fixtures.json &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true' EXIT

# wait for the service to accept/ping
for _ in $(seq 1 200); do
  if python3 -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8123/ping',timeout=1)" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

python3 /app/grid.py maze-0 --port 8123 --out /app/map.txt

[ -s /app/map.txt ]
kill "$SRV" 2>/dev/null || true
echo "solve.sh: basalt-vault mapped for maze-0"