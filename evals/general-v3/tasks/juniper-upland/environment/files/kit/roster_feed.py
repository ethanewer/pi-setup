#!/usr/bin/env python3
"""Roster snapshot feed for the Juniper Upland scheduling desk.

This is the *provided* helper that the coordinator is expected to reuse. It
takes exactly one command-line argument (a member short-name) and prints that
member's deterministic attendance snapshot to stdout. The snapshot is derived
from the member name alone, so it is stable across runs.

Calling convention:  python3 roster_feed.py <member>
  - no argument          -> prints usage to stderr, exit 1
  - unknown member       -> prints error to stderr, exit 2
  - known member         -> prints snapshot to stdout, exit 0
"""
import hashlib
import sys

# Fixed roster whose snapshots we can produce. These are the only members whose
# stdout is ever captured by the scheduling desk.
MEMBERS = ("ada", "ben", "carol", "gwen")

_DESKS = ("pavilion-a", "pavilion-b", "ridge-top", "west-bay", "east-bay")
_WIND = ("calm", "brisk", "gusting", "still")


def snapshot(member):
    seed = ("juniper-upland-roster::" + member).encode("utf-8")
    h = hashlib.sha256(seed).hexdigest()
    offset = int(h[:2], 16)          # 0..255 minutes past 07:30 UTC
    desk = _DESKS[int(h[2:4], 16) % len(_DESKS)]
    wind = _WIND[int(h[4:6], 16) % len(_WIND)]
    station = int(h[6:8], 16) % 24
    guard = 1 + int(h[8:10], 16) % 4
    start_min = 390 + offset            # 07:30 plus offset
    end_min = start_min + 240 + 60 * guard
    start_hh, start_mm = divmod(start_min, 60)
    end_hh, end_mm = divmod(end_min % (24 * 60), 60)
    return (
        "MEMBER={}\n".format(member)
        + "BASE=2026-03-16\n"
        + "POST={}\n".format(desk)
        + "WIND={}\n".format(wind)
        + "STATION={}\n".format(station)
        + "SHIFT_START={:02d}:{:02d}Z\n".format(start_hh, start_mm)
        + "SHIFT_END={:02d}:{:02d}Z\n".format(end_hh, end_mm)
        + "GUARD={}\n".format(guard)
    )


def main(argv):
    if len(argv) != 2:
        sys.stderr.write(
            "usage: python3 roster_feed.py <member>\n"
            "members: {}\n".format(", ".join(MEMBERS))
        )
        return 1
    member = argv[1]
    if member not in MEMBERS:
        sys.stderr.write("unknown member: {}\n".format(member))
        return 2
    sys.stdout.write(snapshot(member))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))