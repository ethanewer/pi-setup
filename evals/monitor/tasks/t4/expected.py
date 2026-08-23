#!/usr/bin/env python3
"""Ground truth for task t4. Usage: expected.py <seed>"""
import json
import random
import sys

seed = sys.argv[1] if len(sys.argv) > 1 else "0"
r = random.Random(f"{seed}:t4:batch")
dur = r.randint(90, 180)
print(json.dumps({
    "duration": dur,
    "error_count": 3,
    "warn_count": 5,
    "final_line": "BATCH FINISHED rc=0",
}))
