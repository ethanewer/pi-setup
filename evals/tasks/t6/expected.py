#!/usr/bin/env python3
"""Ground truth for task t6. Usage: expected.py <seed>"""
import json
import random
import sys

seed = sys.argv[1] if len(sys.argv) > 1 else "0"
r = random.Random(f"{seed}:t6:export")
print(json.dumps({
    "duration": r.randint(150, 210),
    "completion_marker": "EXPORT COMPLETE",
}))
