#!/usr/bin/env python3
"""Visible sanity check for the wickkit repairs (not graded).

Run `python3 /app/selfcheck.py` after applying your fix requests; every
case must PASS once all five audited defects are repaired.
"""
import sys

sys.path.insert(0, "/app/lib")
import wickkit  # noqa: E402

CASES = [
    ("unit_cost", (100, 4), 25),
    ("bulk_total", (100, 12), 1140),
    ("bulk_total", (100, 11), 1100),
    ("wick_length", (4,), 2.5),
    ("melt_pool", (5.0,), 4.0),
    ("melt_pool", (0.5,), 1.0),
    ("batch_rows", (3,), [0, 1, 2]),
]

failures = 0
for name, args, want in CASES:
    got = getattr(wickkit, name)(*args)
    ok = got == want
    print("%s %s%r -> %r (want %r)" % ("PASS" if ok else "FAIL", name, args, got, want))
    failures += 0 if ok else 1
print("selfcheck: %d/%d passed" % (len(CASES) - failures, len(CASES)))
sys.exit(1 if failures else 0)
