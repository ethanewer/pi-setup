#!/bin/bash
set -euo pipefail

cat > /app/server.py <<'PYEOF'
import threading

lock = threading.Lock()
total = 0
increments = {}
DONE = []

def worker(worker_id):
    global total
    for _ in range(200):
        with lock:
            total = total + 1
            increments[worker_id] = increments.get(worker_id, 0) + 1

threads = []
for i in range(4):
    t = threading.Thread(target=worker, args=(i,))
    threads.append(t)
    t.start()
for t in threads:
    t.join()

with open('/app/state.txt', 'w') as f:
    f.write(f"total={total}\n")
    f.write(f"keys={len(increments)}\n")
PYEOF

python3 /app/server.py