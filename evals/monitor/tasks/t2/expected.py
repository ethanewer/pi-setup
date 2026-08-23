#!/usr/bin/env python3
"""Ground truth for task t2. Usage: expected.py <seed>"""
import json
import random
import sys

seed = sys.argv[1] if len(sys.argv) > 1 else "0"

r = random.Random(f"{seed}:t2:data")
total = 0.0
rows = 0
skipped = 0
for i in range(2000):
    amount = f"{r.uniform(1, 500):.2f}"
    if i == 1337:
        amount = "N/A"
    qty = r.randint(1, 9)
    try:
        total += float(amount) * qty
        rows += 1
    except ValueError:
        skipped += 1

pace = random.Random(f"{seed}:t2:pace").uniform(0.03, 0.05)
print(json.dumps({
    "rows": rows,
    "skipped": skipped,
    "total": round(total, 2),
    "crash_row": 1337,
    "approx_seconds_to_crash": round(1337 * pace),
    "approx_full_run_seconds": round(2000 * pace),
}))
