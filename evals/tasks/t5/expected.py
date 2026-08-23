#!/usr/bin/env python3
"""Ground truth for task t5. Usage: expected.py <seed> (seed ignored; data is static)"""
import csv
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "fixture", "data")


def is_prime(n):
    if n < 2:
        return False
    for d in range(2, int(n**0.5) + 1):
        if n % d == 0:
            return False
    return True


nums = [int(x) for x in open(os.path.join(DATA, "nums.txt")).read().split()]
with open(os.path.join(DATA, "orders.csv")) as f:
    ok = sum(1 for row in csv.DictReader(f) if row["status"] == "OK")
print(json.dumps({
    "prime_sum": sum(n for n in nums if is_prime(n)),
    "ok_rows": ok,
    "greet_tests_must_pass": True,
}))
