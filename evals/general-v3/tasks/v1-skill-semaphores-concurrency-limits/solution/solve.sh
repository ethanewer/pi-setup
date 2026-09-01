#!/bin/bash
# Oracle solution for skill-semaphores-concurrency-limits.
set -euo pipefail

cat > /app/limited.py <<'PYEOF'
#!/usr/bin/env python3
import json
import threading
import time

LIMIT = 4
TOTAL = 30

sem = threading.BoundedSemaphore(LIMIT)
lock = threading.Lock()
current = 0
peak = 0
completed = 0


def worker(i):
    global current, peak, completed
    sem.acquire()
    with lock:
        current += 1
        if current > peak:
            peak = current
    try:
        time.sleep(0.02)
    finally:
        with lock:
            current -= 1
            completed += 1
        sem.release()


threads = [threading.Thread(target=worker, args=(i,)) for i in range(TOTAL)]
for t in threads:
    t.start()
for t in threads:
    t.join()

res = {"limit": LIMIT, "total": TOTAL, "completed": completed, "peak": peak}
json.dump(res, open("/app/result.json", "w"))
print(res)
PYEOF

python3 /app/limited.py
echo "solution wrote /app/result.json"