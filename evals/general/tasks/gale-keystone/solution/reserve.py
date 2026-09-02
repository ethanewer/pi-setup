#!/usr/bin/env python3
"""Place a reservation through the service API and record the confirmation.

Usage:
    python3 reserve.py --venue "Venue Name" --company "Company Name"

Loads http://127.0.0.1:8129/reserve with the pair, then appends the
returned confirmation record to /app/reservations.json (creating the file
with a JSON array on first use). Prints the confirmation id on stdout.
"""
import argparse
import json
import os

import requests

BASE = "http://127.0.0.1:8129"
OUT = "/app/reservations.json"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--venue", required=True)
    p.add_argument("--company", required=True)
    args = p.parse_args()

    r = requests.post(BASE + "/reserve",
                      json={"venue": args.venue, "company": args.company},
                      timeout=10)
    r.raise_for_status()
    rec = r.json()

    data = []
    if os.path.exists(OUT):
        with open(OUT, "r", encoding="utf-8") as fh:
            try:
                data = json.load(fh)
            except Exception:
                data = []
    if not isinstance(data, list):
        data = []
    data.append(rec)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)

    print(rec["confirmation"])


if __name__ == "__main__":
    main()