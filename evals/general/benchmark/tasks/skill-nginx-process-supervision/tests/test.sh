#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/nginx.conf ] && [ -f /app/supervision.txt ]; then
  if python3 - <<'EOF'
import re, subprocess

cfg = open('/app/nginx.conf').read()
m = re.search(r'worker_processes\s+(\d+)', cfg)
if not m:
    raise SystemExit('worker_processes missing')
n = int(m.group(1))
if not (1 <= n <= 16):
    raise SystemExit(n)

args = subprocess.run(['ps', '-axo', 'args='], capture_output=True, text=True).stdout.splitlines()
master = sum('nginx: master process' in a for a in args)
workers = sum(a.strip() == 'nginx: worker process' for a in args)

rep = open('/app/supervision.txt').read().strip()
if rep != f'running_workers={n}':
    raise SystemExit((rep, n))
if master < 1:
    raise SystemExit('no nginx master process running')
if workers != n:
    raise SystemExit((workers, n))
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt