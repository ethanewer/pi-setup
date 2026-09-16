#!/usr/bin/env python3
"""Deterministic event-workload generator for the enrichd service.

The events resemble production telemetry: for every round, every client emits
exactly one event, and the spelling of the client's identifier cycles through
four collector-variant forms (casing / padding / interior whitespace) with a
per-round collector tag ("~b<round>") appended.  No two events in a run carry
the same wire string for a client, while every spelling normalises to the
same canonical client identity.  Timestamps grow steadily so a load run
spans one or two calendar days.

Usage:
  gen_workload.py --seed S --clients N --rounds R --start-ts TS --out F.jsonl
"""
import argparse
import json
import random

KINDS = ("pageview", "purchase", "click", "cart_add", "login")
AMOUNTS = (0.0, 4.99, 12.5, 27.0, 149.99)


def spellings(base):
    """Four plausible collector spellings of one client identity."""
    return (
        base,
        base.lower() + " ",
        " " + base.upper(),
        base.lower().replace(" ", "   "),
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--clients", type=int, required=True)
    ap.add_argument("--rounds", type=int, required=True)
    ap.add_argument("--start-ts", type=int, default=1772140000)
    ap.add_argument("--step", type=int, default=60,
                    help="seconds between successive events (default 60)")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    bases = ["Acct %03d" % (i + 1) for i in range(args.clients)]
    variants = [spellings(b) for b in bases]

    rows = []
    ts = args.start_ts
    for r in range(args.rounds):
        order = list(range(args.clients))
        rng.shuffle(order)
        for c in order:
            client = variants[c][r % 4] + "~b%d" % r
            kind = KINDS[rng.randrange(len(KINDS))]
            amount = AMOUNTS[rng.randrange(len(AMOUNTS))]
            rows.append({"client": client, "ts": ts, "kind": kind, "amount": amount})
            ts += args.step

    with open(args.out, "w", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row) + "\n")
    print("wrote %d events to %s" % (len(rows), args.out))


if __name__ == "__main__":
    main()