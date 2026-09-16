#!/usr/bin/env python3
"""wale-haven solver: attribute meter readings to monitoring periods.

CLI (exactly three positional arguments, all paths, in this order):

    python3 aggregate.py PERIODS.json EVENTS.csv OUTPUT.json

  PERIODS.json : {"periods": [{"id", "from", "to"}, ...]} — consecutive,
                 non-overlapping periods; `to` of one equals `from` of next.
  EVENTS.csv   : header `timestamp,value`; naive-UTC `YYYY-MM-DDTHH:MM:SS`
                 timestamps, decimal values; readings lie strictly inside the
                 overall span but may fall exactly on an internal boundary.
  OUTPUT.json  : JSON object mapping every period id to its exact total.

Convention implemented (chosen because it treats a period as covering its
start instant but not its end, so a reading at a boundary is counted exactly
once, in the period that begins at that instant): each period is the half-open
interval [from, to); a reading whose timestamp equals a period's `to` (which is
the next period's `from`) belongs to that next period.

Stdlib only. Everything comes from argv; nothing is hard-coded.
"""
import csv
import json
import sys
from datetime import datetime


def main(argv):
    if len(argv) != 3:
        print("usage: aggregate.py PERIODS.json EVENTS.csv OUTPUT.json",
              file=sys.stderr)
        return 2

    periods_path, events_path, out_path = argv

    with open(periods_path) as fh:
        schedule = json.load(fh)["periods"]

    bounds = [(p["id"], datetime.fromisoformat(p["from"]),
               datetime.fromisoformat(p["to"])) for p in schedule]

    totals = {pid: 0.0 for pid, _, _ in bounds}

    with open(events_path, newline="") as fh:
        for row in csv.DictReader(fh):
            ts = datetime.fromisoformat(row["timestamp"].strip())
            value = float(row["value"])
            for pid, frm, to in bounds:
                # half-open: [from, to) — the boundary instant belongs to the
                # period that starts at it, never to the one that ended.
                if frm <= ts < to:
                    totals[pid] += value
                    break

    with open(out_path, "w") as fh:
        json.dump(totals, fh, indent=2, sort_keys=True)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))