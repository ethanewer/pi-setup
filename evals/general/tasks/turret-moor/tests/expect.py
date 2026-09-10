#!/usr/bin/env python3
"""Independent expectation for the turret-moor verifier.

Parses a boxlib "pluto" plotfile directory (the layout yt's
``yt/frontends/amrex`` frontend reads) using only numpy, and computes the
three quantities the agent's analysis must reproduce:

    total_mass_g                 total cell mass of the domain, grams
    mass_weighted_temperature_K  density-weighted mean temperature, kelvin
    cell_count                   number of simulation cells

This is deliberately a plain-numpy paraphrase of the physical integral, not
yt: it is the independently-computed expectation the deliverable's output is
compared against.

Usage: expect.py <dataset-directory>
Prints one JSON object to stdout.
"""

import json
import os
import re
import sys

import numpy as np


def read_dataset(dataset_dir):
    with open(os.path.join(dataset_dir, "Header")) as f:
        # sequential parse, mirroring the boxlib Header layout
        next(f)  # version
        n_fields = int(next(f))
        fields = [next(f).strip() for _ in range(n_fields)]
        next(f)  # dimensionality
        next(f)  # current time
        max_level = int(next(f))
        left = np.array(next(f).split(), dtype="f8")
        right = np.array(next(f).split(), dtype="f8")
        next(f)  # refinement factors
        index_space = next(f)
        next(f)  # timesteps per level
        cell_sizes = [next(f) for _ in range(max_level + 1)]
        next(f)  # geometry
        next(f)  # data-start marker

    m = re.search(
        r"\(\((-?\d+,-?\d+,-?\d+)\) \((-?\d+,-?\d+,-?\d+)\)", index_space
    )
    start = np.array([int(v) for v in m.group(1).split(",")])
    stop = np.array([int(v) for v in m.group(2).split(",")])
    dims = (stop - start + 1).astype("int64")
    assert left.shape == dims.shape and right.shape == dims.shape

    count = int(dims.prod())
    with open(os.path.join(dataset_dir, "Level_0", "CellData"), "rb") as f:
        f.readline()  # FAB text header
        raw = np.fromfile(f, dtype="<f8", count=count * n_fields)
    n = 0
    arrays = {}
    for i, field in enumerate(fields):
        arrays[field] = raw[n : n + count].reshape(dims, order="F")
        n += count

    dx, dy, dz = [((right[i] - left[i]) / dims[i]).item() for i in range(3)]
    volume = dx * dy * dz
    return arrays, volume, count


def main():
    dataset_dir = sys.argv[1]
    arrays, volume, count = read_dataset(dataset_dir)
    density = arrays["density"]
    temperature = arrays["temperature"]
    total_mass_g = float(density.sum() * volume)
    mass_weighted_temperature_K = float(
        (temperature * density).sum() / density.sum()
    )
    print(
        json.dumps(
            {
                "total_mass_g": total_mass_g,
                "mass_weighted_temperature_K": mass_weighted_temperature_K,
                "cell_count": count,
            }
        )
    )


if __name__ == "__main__":
    main()