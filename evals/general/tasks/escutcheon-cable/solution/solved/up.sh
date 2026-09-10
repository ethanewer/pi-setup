#!/usr/bin/env bash
# Bring the cart stack up:
#   collector :127.0.0.1:9100               (span sink)
#   backend   :127.0.0.1:8100               (Go order service)
#   frontend  :127.0.0.1:8000               (Python storefront, the public edge)
#
# The verifier executes this script to start the stack for grading. It builds
# the Go backend from source, launches all three processes in the background
# (redirecting frontend/backend stdout to the structured-log files the grader
# expects), and polls readiness before returning.
set -u
cd /app
mkdir -p .logs runs

# stop anything already started by this script (idempotent)
for f in runs/collector.pid runs/backend.pid runs/frontend.pid; do
  [ -f "$f" ] || continue
  kill "$(cat "$f")" 2>/dev/null || true
  rm -f "$f"
done
sleep 0.2

# 1) build the Go backend from source
if ! (cd services/backend && go build -o /app/runs/backend main.go) 2>.logs/gobuild.err; then
  echo "go build failed" >&2
  sed -n '1,40p' .logs/gobuild.err >&2
  exit 1
fi

# 2) collector (span sink)
nohup python3 services/collector/collector.py >.logs/collector.out 2>&1 &
echo $! > runs/collector.pid
sleep 0.3

# 3) backend (structured logs land in .logs/backend.jsonl)
nohup /app/runs/backend >.logs/backend.jsonl 2>&1 &
echo $! > runs/backend.pid

# 4) frontend (structured logs land in .logs/frontend.jsonl)
nohup python3 services/frontend/frontend.py >.logs/frontend.jsonl 2>&1 &
echo $! > runs/frontend.pid

# 5) wait for readiness
ok=0
for i in $(seq 1 80); do
  if curl -sf http://127.0.0.1:8000/health >/dev/null 2>&1 \
     && curl -sf http://127.0.0.1:8100/health >/dev/null 2>&1 \
     && curl -sf http://127.0.0.1:9100/health >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 0.25
done
if [ "$ok" != 1 ]; then
  echo "cart stack did not become ready" >&2
  echo "-- collector --"; tail -5 .logs/collector.out 2>/dev/null || true
  echo "-- backend --";   tail -5 .logs/backend.jsonl 2>/dev/null || true
  echo "-- frontend --";  tail -5 .logs/frontend.jsonl 2>/dev/null || true
  exit 1
fi

echo "cart stack up (frontend 8000, backend 8100, collector 9100)"
