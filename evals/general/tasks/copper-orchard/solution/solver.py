#!/usr/bin/env python3
"""copper-orchard: summarize a noisy experiment ledger.

Reads a CSV with a `device` column and a `reading` column (parsed by header
name; column order and extra columns are irrelevant), and writes a JSON summary
of per-device medians, an overall trimmed mean, and a 90% bootstrap interval
for the overall mean.

Usage:
    python3 solve.py [input.csv [output.json]]

Defaults: input=/app/readings.csv, output=/app/answer.json.
"""
import csv
import json
import math
import random
import sys

INPUT_DEFAULT = "/app/readings.csv"
OUTPUT_DEFAULT = "/app/answer.json"
SEED = 42
N_RESAMPLES = 2000
ALPHA = 0.10  # -> 90% two-sided interval


def parse_reading(value):
    """Return float for a numeric string, else None (blank / non-numeric)."""
    if value is None:
        return None
    s = value.strip()
    if s == "":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def load(input_path):
    """Return dict device_name -> list[float] of valid readings.

    Rows are matched by header name. Blank readings, non-numeric readings,
    and rows with an empty device name are skipped. Device order in the CSV is
    not important; the summary is produced in sorted device-name order.
    """
    per_device = {}
    with open(input_path, newline="") as fh:
        for row in csv.DictReader(fh):
            # Normalize header names so whitespace-padded headers still parse.
            clean = {key.strip() if key else key: val for key, val in row.items()}
            device = (clean.get("device") or "").strip()
            if device == "":
                continue
            value = parse_reading(clean.get("reading", ""))
            if value is None:
                continue
            per_device.setdefault(device, []).append(value)
    return per_device


def median(values):
    """Classic median of a list of floats (averages the two middles)."""
    s = sorted(values)
    n = len(s)
    if n % 2 == 1:
        return s[n // 2]
    return (s[n // 2 - 1] + s[n // 2]) / 2.0


def trimmed(values):
    """Observations kept after dropping the lowest and highest of each device.

    Devices with fewer than three valid readings contribute all of them.
    """
    if len(values) >= 3:
        s = sorted(values)
        return s[1:-1]
    return list(values)


def pooled_trimmed(per_device):
    pool = []
    for device in sorted(per_device):
        pool.extend(trimmed(per_device[device]))
    return pool


def percentile(sorted_values, q):
    """Linear-interpolation quantile on a sorted sequence."""
    if not sorted_values:
        return None
    n = len(sorted_values)
    pos = (n - 1) * q
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return sorted_values[lo]
    frac = pos - lo
    return sorted_values[lo] * (1.0 - frac) + sorted_values[hi] * frac


def bootstrap90(pool):
    """90% bootstrap (empirical) confidence interval for the pooled mean.

    Non-parametric: resample the observations with replacement, take the 5th
    and 95th percentiles of the resampled means. Fixed seed => deterministic.
    """
    if not pool:
        return None
    n = len(pool)
    rng = random.Random(SEED)
    means = []
    for _ in range(N_RESAMPLES):
        total = 0.0
        for _ in range(n):
            total += pool[rng.randrange(n)]
        means.append(total / n)
    means.sort()
    return [percentile(means, ALPHA), percentile(means, 1.0 - ALPHA)]


def summarize(input_path):
    per_device = load(input_path)
    pool = pooled_trimmed(per_device)

    devices = {name: median(vals) for name, vals in sorted(per_device.items())}
    trimmed_mean = (sum(pool) / len(pool)) if pool else None
    ci = bootstrap90(pool)
    return {"devices": devices, "trimmed_mean": trimmed_mean, "bootstrap90": ci}


def main(argv):
    inp = argv[1] if len(argv) > 1 else INPUT_DEFAULT
    out = argv[2] if len(argv) > 2 else OUTPUT_DEFAULT
    result = summarize(inp)
    with open(out, "w") as fh:
        json.dump(result, fh)
    return result


if __name__ == "__main__":
    main(sys.argv)