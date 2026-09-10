#!/bin/bash
# Oracle for culvert-keel. Installs the real Go service source into the
# deliverable path, writes the launch script the same way the agent must,
# then PROVES the stack by building and smoke-testing the server against the
# visible fixture. Never reads /tests.
set -eu

mkdir -p /app/server
cp /solution/main.go /app/server/main.go

cat > /app/run_server.sh <<'RUNEOF'
#!/bin/bash
# Launcher for the culvert-keel registry service.
# Usage: bash /app/run_server.sh CONFIG_DIR PORT
# Builds the service (if needed), starts it in the background, records the
# PID in /app/server.pid, and returns immediately; the callee polls
# /healthz for readiness. Server stdout/stderr go to /app/server.out.log.
set -eu
CFG="${1:?usage: run_server.sh CONFIG_DIR PORT}"
PORT="${2:?usage: run_server.sh CONFIG_DIR PORT}"
cd /app/server || exit 1
export GOCACHE=/tmp/gocache
if [ ! -x ./server-bin ] || [ main.go -nt server-bin ]; then
  go build -o server-bin main.go || { echo "go build failed" >&2; exit 1; }
fi
if [ -f /app/server.pid ]; then
  kill "$(cat /app/server.pid)" 2>/dev/null || true
  rm -f /app/server.pid
fi
nohup ./server-bin "$CFG" "$PORT" > /app/server.out.log 2>&1 &
echo $! > /app/server.pid
RUNEOF
chmod +x /app/run_server.sh

# ---- real smoke test: build + start + exercise the contract ----
cd /app/server
export GOCACHE=/tmp/gocache
go build -o server-bin main.go
rm -f /app/server.log
bash /app/run_server.sh /app/config 18080
OK=0
for i in $(seq 1 50); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/healthz 2>/dev/null || true)
  if [ "$CODE" = "200" ]; then OK=1; break; fi
  sleep 0.2
done
if [ "$OK" != "1" ]; then
  echo "smoke: server never became ready" >&2
  cat /app/server.out.log >&2 || true
  exit 1
fi
C=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer token-alpha" http://127.0.0.1:18080/api/v1/registry)
[ "$C" = "200" ] || { echo "smoke: authed GET returned $C" >&2; exit 1; }
C=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/api/v1/registry)
[ "$C" = "401" ] || { echo "smoke: unauth GET returned $C" >&2; exit 1; }
# measured burst against the visible fixture (capacity 6)
SEQ=""
for i in $(seq 1 8); do
  SEQ="$SEQ $(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer token-delta" http://127.0.0.1:18080/api/v1/registry)"
done
echo "smoke burst (cap 6):$SEQ"
case "$SEQ" in *429*) : ;; *) echo "smoke: no 429 in burst" >&2; exit 1 ;; esac
kill "$(cat /app/server.pid)" 2>/dev/null || true
rm -f /app/server.pid
echo "oracle built, launched and verified the service"