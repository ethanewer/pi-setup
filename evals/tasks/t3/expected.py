#!/usr/bin/env python3
"""Ground truth for task t3. Usage: expected.py <seed>

Note: the build id is intentionally NOT listed here. It is derived from the live
server's pid (srv/server.pid) by the scorer, so it cannot be precomputed from source.
"""
import json
import random
import sys

seed = sys.argv[1] if len(sys.argv) > 1 else "0"
r = random.Random(f"{seed}:t3:boot")
print(json.dumps({
    "boot_delay": r.randint(45, 120),
    "ready_line_marker": "listening on",
}))
