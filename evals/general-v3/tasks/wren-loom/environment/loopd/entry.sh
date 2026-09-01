#!/usr/bin/env bash
# Container entrypoint: start the loopd list daemon (which reads its canonical
# config at /etc/loopd/lists.conf), then run the real command.
set -u
mkdir -p /run
nohup python3 /opt/loopd/loopd.py >> /var/log/loopd.log 2>&1 &

for _ in $(seq 1 100); do
  resp=$(python3 -c "import socket;s=socket.create_connection(('127.0.0.1',7871),1);s.sendall(b'PING\n');print(s.recv(64).decode().strip())" 2>/dev/null || true)
  [ "${resp:-}" = "PONG" ] && break
  sleep 0.2
done

exec "$@"
