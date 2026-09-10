#!/usr/bin/env python3
"""Reference analysis for turret-moor.

Loads a boxlib 'pluto' snapshot with yt's own loader, computes the domain
total mass and the density-weighted mean temperature through yt's field and
derived-quantity machinery, and writes the result JSON.

Usage: analyze.py <dataset-directory> <output.json>
"""

import json
import sys

import yt


def analyze(dataset_dir):
    ds = yt.load(dataset_dir)
    ad = ds.all_data()
    total_mass = float(ad.quantities.total_mass()[0].in_units("g"))
    mass_weighted_temperature = float(
        ad.quantities.weighted_average_quantity(
            "temperature", weight="density"
        ).in_units("K")
    )
    cell_count = int(ds.domain_dimensions.prod())
    return {
        "total_mass_g": total_mass,
        "mass_weighted_temperature_K": mass_weighted_temperature,
        "cell_count": cell_count,
    }


def main():
    dataset_dir, out_path = sys.argv[1], sys.argv[2]
    result = analyze(dataset_dir)
    with open(out_path, "w") as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result))


if __name__ == "__main__":
    main()