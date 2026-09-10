"""Command-line interface for dutywheel."""
from __future__ import annotations

import argparse
from datetime import date

from dutywheel.crew import load_roster
from dutywheel.rotation import pick
from dutywheel.schedule import build_weeks, render_table


def cmd_next(args):
    roster = load_roster(args.roster)
    print(pick(roster["members"]))
    return 0


def cmd_schedule(args):
    roster = load_roster(args.roster)
    start = date.fromisoformat(args.start)
    table = build_weeks(roster, start, weeks=args.weeks)
    print(render_table(table), end="")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="dutywheel",
        description="on-call rotation for service crews",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_next = sub.add_parser("next", help="print the next on-call member id")
    p_next.add_argument("roster", help="path to a crew roster JSON")
    p_next.set_defaults(handler=cmd_next)

    p_sched = sub.add_parser("schedule", help="print a weekly on-call schedule")
    p_sched.add_argument("roster", help="path to a crew roster JSON")
    p_sched.add_argument("--start", required=True,
                         help="first week's Monday, YYYY-MM-DD")
    p_sched.add_argument("--weeks", type=int, default=4)
    p_sched.set_defaults(handler=cmd_schedule)

    args = parser.parse_args(argv)
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())