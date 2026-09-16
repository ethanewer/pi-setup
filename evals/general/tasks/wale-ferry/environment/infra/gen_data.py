#!/usr/bin/env python3
"""Deterministic generator for the wale-ferry order_facts seed dataset.

Produces one tab-separated row per synthetic order, matching the column order
of the LOAD DATA statement in seed.sql:

    customer_id<TAB>region<TAB>channel<TAB>status<TAB>placed_at<TAB>total<TAB>items

The PRNG is seeded so every build and every reset materialises byte-identical
rows; the graders' golden result files are computed against exactly this data.
"""
import datetime
import random
import sys

RNG = random.Random(20260407)
REGIONS = ["north", "south", "east", "west", "central", "coastal"]
CHANNELS = ["online", "store", "kiosk", "partner"]
STATUSES = ["confirmed", "shipped", "delivered", "returned", "cancelled"]

N_ROWS = 1_000_000
BASE0 = datetime.datetime(2024, 1, 1)
SPAN = (
    datetime.datetime(2025, 12, 31, 23, 59, 59) - BASE0
).total_seconds()


def main() -> int:
    out_path = sys.argv[1] if len(sys.argv) > 1 else "/opt/warehouse/order_facts.tsv"
    with open(out_path, "w", encoding="utf-8") as fh:
        for _ in range(N_ROWS):
            cid = RNG.randrange(1, 20001)
            region = REGIONS[RNG.randrange(len(REGIONS))]
            channel = CHANNELS[RNG.randrange(len(CHANNELS))]
            status = STATUSES[RNG.randrange(len(STATUSES))]
            ts = BASE0 + datetime.timedelta(
                seconds=RNG.random() * SPAN
            )
            total = round(RNG.gauss(82, 40) + 8, 2)
            if total < 2:
                total = 2.0
            items = RNG.randrange(1, 26)
            fh.write(
                f"{cid}\t{region}\t{channel}\t{status}\t{ts:%Y-%m-%d %H:%M:%S}"
                f"\t{total:.2f}\t{items}\n"
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())