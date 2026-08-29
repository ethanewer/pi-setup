#!/bin/bash
set -eu
# Oracle for saffron-chain. Writes a real Metropolis sampler to /app/sample.py,
# then RUNS it on the visible config to produce /app/samples.txt. Does not read
# /tests and does not cat any precomputed answer.

cat > /app/sample.py <<'PY'
#!/usr/bin/env python3
"""Bounded random-walk Metropolis sampler for a truncated normal.

Usage:
    python3 sample.py [CONFIG] [OUT]

CONFIG:  key=value file (default /app/target.txt)
OUT:     path to write one sample per line (default /app/samples.txt)

Config keys:
    support = lo,hi      support bounds of the density
    center  = c          mode / center of the Gaussian
    scale   = v          variance of the untruncted Gaussian
    n       = int        number of retained draws after burn-in
    burn_in = int        number of warm-up draws discarded
    seed    = int        RNG seed (deterministic reproducibility)

Target density (up to normalising constant):
    f(x) ∝ exp( -(x - center)^2 / (2 * scale) )   for x in [support.lo,
support.hi], and 0 outside. So 'scale' is the Gaussian variance; support
truncates the distribution.
"""
import math
import random
import sys


def load_config(path):
    params = {}
    with open(path, "r") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            params[key.strip()] = val.strip()
    return params


def density_fac(x, center, scale):
    """Proportional target log-kernel, used for Metropolis ratios."""
    return math.exp(-((x - center) ** 2) / (2.0 * scale))


def main():
    config_path = sys.argv[1] if len(sys.argv) > 1 else "/app/target.txt"
    out_path = sys.argv[2] if len(sys.argv) > 2 else "/app/samples.txt"

    p = load_config(config_path)
    lo, hi = (float(v) for v in p["support"].split(","))
    center = float(p["center"])
    scale = float(p["scale"])
    n = int(p["n"])
    burn_in = int(p["burn_in"])
    seed = int(p["seed"])

    rng = random.Random(seed)
    # Proposal step (bounded random walk): Gaussian proposal with std
    # proportional to the target width, clipped to the support.
    prop = 0.8 * math.sqrt(scale)

    x = min(max(center, lo), hi)  # start inside the support

    def propose(current):
        while True:
            cand = current + rng.gauss(0.0, prop)
            if lo <= cand <= hi:
                return cand

    # burn-in phase (discarded)
    for _ in range(burn_in):
        cand = propose(x)
        if rng.random() < (density_fac(cand, center, scale) /
                           density_fac(x, center, scale)):
            x = cand

    samples = []
    append = samples.append
    for _ in range(n):
        cand = propose(x)
        if rng.random() < (density_fac(cand, center, scale) /
                           density_fac(x, center, scale)):
            x = cand
        append(x)

    with open(out_path, "w") as fh:
        fh.write("\n".join("%.6f" % v for v in samples) + "\n")

    print("wrote %d samples to %s (seed=%d)" % (n, out_path, seed))


if __name__ == "__main__":
    main()
PY

chmod +x /app/sample.py
# Run the deliverable for real to produce the visible-case output.
python3 /app/sample.py /app/target.txt /app/samples.txt >/tmp/solve_run.out 2>&1
[ "$(wc -l < /app/samples.txt)" -eq 12000 ] && echo "oracle: wrote 12000 samples"