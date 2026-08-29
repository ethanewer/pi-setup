#!/usr/bin/env python3
"""Granite Grove overlap finder.

Reads an availability schedule CSV and computes pairwise overlaps between
different people's slots that occur on the same day and overlap by more than
zero minutes.  Skips malformed rows.  Writes a JSON array to stdout.

Input CSV columns: slot_id,person,day,start,end   (times are HH:MM, 24h)
Result entry: {"people": [...person_a, person_b...], "day": "...",
              "overlap_start":"HH:MM","overlap_end":"HH:MM","minutes":N}
Sorted by minutes desc, then day, then person labels.
"""
import csv
import json
import sys

DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


def to_min(t):
    try:
        hh, mm = t.strip().split(":")
        return int(hh) * 60 + int(mm)
    except Exception:
        return None


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: find_overlaps.py availability.csv\n")
        sys.exit(2)
    rows = []
    with open(sys.argv[1], newline="") as fh:
        for line in csv.DictReader(fh):
            sid = line.get("slot_id", "").strip()
            person = line.get("person", "").strip()
            day = (line.get("day", "") or "").strip()
            start = to_min(line.get("start", ""))
            end = to_min(line.get("end", ""))
            if sid and person and day in DAYS and start is not None and end is not None:
                if end > start:
                    rows.append({"sid": sid, "person": person, "day": day,
                                 "start": start, "end": end})

    by_day = {}
    for r in rows:
        by_day.setdefault(r["day"], []).append(r)

    results = []
    for day in by_day:
        slots = by_day[day]
        for i in range(len(slots)):
            for j in range(i + 1, len(slots)):
                a, b = sorted([slots[i], slots[j]], key=lambda x: x["person"])
                lo = max(a["start"], b["start"])
                hi = min(a["end"], b["end"])
                if hi - lo > 1:
                    minutes = hi - lo
                    results.append({
                        "person": [a["person"], b["person"]],
                        "day": day,
                        "overlap_start": f"{lo // 60:02d}:{lo % 60:02d}",
                        "overlap_end": f"{hi // 60:02d}:{hi % 60:02d}",
                        "minutes": minutes,
                    })
    results.sort(key=lambda r: (-r["minutes"], DAYS.index(r["day"]),
                                tuple(r["person"])))
    sys.stdout.write(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()