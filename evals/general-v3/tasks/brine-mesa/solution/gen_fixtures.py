#!/usr/bin/env python3
"""Generate brine-mesa fixtures (deterministic, seeded).

Schema of a fixture file:
  line 1: N CUTOFF DT STEPS LX LY LZ
  then N lines: x y z vx vy vz
"""
import random
import sys

FIXTURES = {
    "fixture_main.txt": dict(seed=4102, N=12000, cutoff=2.0, dt=0.05, steps=12, L=50.0),
    "ridge.txt":        dict(seed=811,  N=1500,  cutoff=2.5, dt=0.03, steps=25, L=6.0),
    "shelf.txt":        dict(seed=5227, N=20000, cutoff=2.0, dt=0.04, steps=20, L=60.0),
    "embankment.txt":   dict(seed=90211, N=100000, cutoff=2.5, dt=0.02, steps=60, L=140.0),
}


def gen(path, seed, N, cutoff, dt, steps, L):
    rng = random.Random(seed)
    with open(path, "w") as f:
        f.write(f"{N} {cutoff} {dt} {steps} {L} {L} {L}\n")
        for _ in range(N):
            x, y, z = (rng.uniform(0.0, L) for _ in range(3))
            vx, vy, vz = (rng.uniform(-0.05, 0.05) for _ in range(3))
            f.write(f"{x!r} {y!r} {z!r} {vx!r} {vy!r} {vz!r}\n")
    print("wrote", path)


if __name__ == "__main__":
    for name, kw in FIXTURES.items():
        gen(sys.argv[1] + "/" + name, **kw)
