#!/bin/bash
# echo-latch oracle. Installs the reference reclaim tool and RUNS it against the
# live keeper to produce /app/reclaimed_payload.bin. Never reads /tests.
set -eu

cp /solution/reclaim_fd.py /app/reclaim_fd.py
chmod +x /app/reclaim_fd.py

python3 /app/reclaim_fd.py /app/spool/.latch.pid /app/reclaimed_payload.bin

[ -f /app/reclaim_fd.py ] || { echo "oracle: missing /app/reclaim_fd.py" >&2; exit 1; }
[ -f /app/reclaimed_payload.bin ] || { echo "oracle: missing /app/reclaimed_payload.bin" >&2; exit 1; }
echo "oracle done: /app/reclaim_fd.py and /app/reclaimed_payload.bin"
