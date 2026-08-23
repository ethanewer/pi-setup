#!/usr/bin/env python3
"""Ground truth for task t7. Usage: expected.py <seed>"""
import json
import math
import random
import sys

seed = sys.argv[1] if len(sys.argv) > 1 else "0"
r = random.Random(f"{seed}:t7:train")
total = r.randint(220, 280)
steps = math.ceil(total / 70) * 100
print(json.dumps({
    "duration": total,
    "checkpoint_interval": 70,
    "final_step": steps,
    "completion_marker": "TRAINING COMPLETE",
}))
