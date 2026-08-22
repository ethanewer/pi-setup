#!/usr/bin/env python3
"""Ground truth for task t5. Usage: expected.py <seed>"""
import hashlib
import json
import random
import sys

seed = sys.argv[1] if len(sys.argv) > 1 else "0"
ra = random.Random(f"{seed}:t5:a")
rb = random.Random(f"{seed}:t5:b")
print(json.dumps({
    "a_duration": ra.randint(60, 140),
    "a_checksum": hashlib.sha256(f"{seed}:t5:a:sum".encode()).hexdigest()[:10],
    "b_duration": rb.randint(90, 200),
    "b_checksum": hashlib.sha256(f"{seed}:t5:b:sum".encode()).hexdigest()[:10],
}))
