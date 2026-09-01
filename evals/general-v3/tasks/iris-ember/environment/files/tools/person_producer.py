#!/usr/bin/env python3
"""Meridian per-person schedule snapshot producer.

Prints a small deterministic per-person "schedule snapshot" block to stdout.
See its own --help for the calling convention. No arguments other than
--person are required. Reads the roster table in this same directory.
"""
import argparse
import json
import os
import sys

BASE = os.path.dirname(os.path.abspath(__file__))
ROSTER = os.path.join(BASE, "roster.json")


def main():
    p = argparse.ArgumentParser(description="per-person schedule snapshot")
    p.add_argument("--person", required=True, help="attendee key")
    args = p.parse_args()

    with open(ROSTER, encoding="utf-8") as fh:
        roster = json.load(fh)

    if args.person not in roster:
        sys.exit("unknown person %r" % args.person)

    rec = roster[args.person]
    print("PERSON=%s" % args.person)
    print("TOPIC=%s" % rec["topic"])
    print("SESSION_MIN=%d" % rec["session_min"])
    print("SNAPSHOT=%s" % rec["snapshot_token"])
    print("SLOT=%s" % rec["slot"])


if __name__ == "__main__":
    main()