#!/usr/bin/env python3
"""Ground truth for task t3. Usage: expected.py <seed>"""
import hashlib
import json
import random
import sys

seed = sys.argv[1] if len(sys.argv) > 1 else "0"
r = random.Random(f"{seed}:t3:boot")
print(json.dumps({
    "boot_delay": r.randint(45, 120),
    "port": 8531,
    "build": hashlib.sha256(f"{seed}:t3:build".encode()).hexdigest()[:12],
    "ready_line_marker": "listening on",
}))
