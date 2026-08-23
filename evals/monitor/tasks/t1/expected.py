#!/usr/bin/env python3
"""Ground truth for task t1. Usage: expected.py <seed>"""
import json
import random
import sys

seed = sys.argv[1] if len(sys.argv) > 1 else "0"
r = random.Random(f"{seed}:t1:suite")
print(json.dumps({
    "suite_duration": r.randint(90, 180),
    "suite_final_line": "TEST SUITE COMPLETE: 47 passed, 0 failed",
    "unit_tests_must_pass": True,
}))
