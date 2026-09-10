#!/usr/bin/env python3
"""Deterministic NDJSON workload generator for the marline-trough hidden
cases. Independent from the fixture's own scripts/gen_fixture.mjs: this is
how the verifier manufactures the large inputs it grades on.

Writes <rows> lines of NDJSON sensor records, seeded, plus a small share of
blank lines, malformed lines, unknown-sensor rows, and rows missing the
"site" field, mirroring the tolerant-input contract the fixture documents.
Usage:

    python3 gen.py <params.json> <output.ndjson>
"""
import json
import random
import sys


def struct(rng, sensors, sites, rows, out_path):
    """Emit rows deterministically. sensors: {token: [lo, hi]} (ints)."""
    sites = list(sites)
    tokens = list(sensors)
    ts = 1_700_000_000
    with open(out_path, "w", encoding="ascii") as fh:
        for _ in range(rows):
            roll = rng.randrange(100)
            if roll < 2:
                fh.write("\n")  # blank line
                continue
            if roll < 3:
                fh.write("{ this is not json\n")  # malformed line
                continue
            # ~2% of rows carry an unknown sensor ("therm"), mirroring the
            # fixture's gen_fixture.mjs and the README's "small share of
            # unknown-sensor rows" contract. The comparison is deliberate:
            # roll in {98, 99} (2%) yields the unknown sensor, everything
            # below a real sensor token.
            sensor = "therm" if roll >= 98 else rng.choice(tokens)
            lo, hi = sensors.get(sensor, sensors[rng.choice(tokens)])
            raw = rng.randint(lo, hi)
            site = rng.choice(sites)
            ts += rng.randint(1, 5)
            if rng.randrange(200) == 0:
                # missing the "site" field
                fh.write('{"ts":%d,"sensor":"%s","raw":%d,"unit":"u"}\n'
                         % (ts, sensor, raw))
            else:
                fh.write('{"site":"%s","ts":%d,"sensor":"%s","raw":%d,"unit":"u"}\n'
                         % (site, ts, sensor, raw))


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: gen.py <params.json> <output.ndjson>", file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8") as fh:
        params = json.load(fh)
    rng = random.Random(params["seed"])
    struct(rng, params["sensors"], params["sites"],
           int(params["rows"]), sys.argv[2])
    return 0


if __name__ == "__main__":
    sys.exit(main())