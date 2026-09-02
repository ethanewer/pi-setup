#!/usr/bin/env python3
"""cedar-summit hidden probe: plan optimality.

The booking desk only checks feasibility; the graded plan must be the one the
group actually chooses under the documented decision rule. Compares the
deliverable against the exact expected optimum derived from the hidden group
state, and re-runs the full booking validation.
"""
import json
import sys

sys.path.insert(0, "/opt/offsite/services")

from offsite_common import validate_plan  # noqa: E402

PLAN_PATH = "/app/offsite_plan.json"

# The unique optimum:
#   date   2026-03-12 — the only day in all three availabilities;
#   activity board-game-cafe — budget (55 EUR cooking-class out) and hard
#          constraints (trail-hike out for all three) leave escape-room and
#          board-game-cafe; rank sums are 1+2+3=6 vs 2+1+1=4, so
#          board-game-cafe wins;
#   venue  meeple-and-mug — fixed by the catalog;
#   start  15:00 — the 11:00 slot collides with Priya's release-day debrief
#          (blocked until 12:30 on 2026-03-12).
EXPECTED = {
    "date": "2026-03-12",
    "activity": "board-game-cafe",
    "venue": "meeple-and-mug",
    "start_time": "15:00",
}


def main() -> int:
    try:
        plan = json.load(open(PLAN_PATH))
    except Exception as exc:
        print("cannot read the plan: %s" % exc)
        return 1

    if plan != EXPECTED:
        print("plan %s is not the group optimum %s" % (plan, EXPECTED))
        return 1

    ok, reason = validate_plan(plan)
    if not ok:
        print("expected optimum failed booking validation: %s" % reason)
        return 1

    print("plan probe passed: %s" % json.dumps(plan))
    return 0


if __name__ == "__main__":
    sys.exit(main())
