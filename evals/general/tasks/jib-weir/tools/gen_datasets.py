#!/usr/bin/env python3
"""Deterministic generator for the jib-weir media-catalogue datasets.

Produces:
  environment/files/data/media.json          (visible fixture, 48 items)
  tests/hidden/case1/data.json               (41 items, mostly distinct years)
  tests/hidden/case2/data.json               (23 items, heavy year ties)
  tests/hidden/case3/data.json               (97 items, extreme year ties)

Every dataset is a JSON object {"items": [ {title, year, rating, medium,
tags}, ... ]}. The API server assigns ids in file order starting at 1, so the
(expected) (year, id)-sorted order is a pure function of the file.
"""
import json
import random
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

TITLES_A = ["ember", "pale", "quiet", "hollow", "golden", "distant", "broken",
            "weathered", "thin", "slow", "borrowed", "sharp", "lost", "narrow",
            "red", "clear", "heavy", "light", "cold", "warm", "ancient", "new"]
TITLES_B = ["tide", "lantern", "hourglass", "cartographer", "heron", "market",
            "orchard", "signal", "passage", "relay", "cinder", "wake", "ridge",
            "harbor", "kestrel", "inlet", "flume", "quarry", "keel", "bell",
            "guild", "moat", "seam", "pylon"]
MEDIUMS = ["film", "series", "documentary", "short"]
TAGS = ["noir", "space", "memoir", "slow", "loud", "teal", "archival",
        "seaside", "cartel", "electro", "verite", "orbital", "acoustic",
        "mono", "found", "maverick", "nordic", "second-act", "woodcut",
        "marble", "steam", "granular", "tidal", "vhs", "beta"]


def make_items(n, years, rng):
    items = []
    for i in range(1, n + 1):
        items.append({
            "title": "%s %s %02d" % (rng.choice(TITLES_A), rng.choice(TITLES_B), i),
            "year": rng.choice(years),
            "rating": rng.randint(0, 100),
            "medium": rng.choice(MEDIUMS),
            "tags": rng.sample(TAGS, rng.randint(0, 5)),
        })
    return items


def write(path, items):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"items": items}, indent=1) + "\n")
    print("%-58s %3d items   %6d bytes" % (str(path.relative_to(ROOT)),
                                           len(items), path.stat().st_size))


def main():
    write(ROOT / "environment/files/data/media.json",
          make_items(48, list(range(1900, 2101)), random.Random(0xC0FFEE)))
    write(ROOT / "tests/hidden/case1/data.json",
          make_items(41, list(range(1912, 2029)), random.Random(0xD15EA5E)))
    write(ROOT / "tests/hidden/case2/data.json",
          make_items(23, [1999, 2001, 2004, 2010, 2013, 2019, 2024, 2026],
                     random.Random(0xBEEF01)))
    write(ROOT / "tests/hidden/case3/data.json",
          make_items(97, [1975, 1984, 1993, 2002, 2011],
                     random.Random(0xFACADE)))


if __name__ == "__main__":
    main()