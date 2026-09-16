"""Weekly on-call schedule.

``build_weeks(roster, start_date, weeks=4)`` builds the coming weeks of an
on-call table, one row per week::

    {"week_start": "2026-11-02", "member_id": "mae-jemison"}

The member for each week is chosen with ``dutywheel.rotation.pick``, and
the previous cycle's member is threaded through so the wheel never assigns
the same member two consecutive weeks.
"""
from __future__ import annotations

from datetime import date, timedelta

from dutywheel.rotation import pick


def build_weeks(roster, start_date, weeks=4, now=None):
    """Return a list of per-week on-call slots starting at *start_date*."""
    if weeks < 1:
        raise ValueError("weeks must be >= 1")
    members = roster["members"]
    rows = []
    previous = None
    day = start_date
    for _ in range(weeks):
        assigned = pick(members, previous=previous, now=now)
        rows.append({"week_start": day.isoformat(), "member_id": assigned["id"]})
        previous = assigned
        day = day + timedelta(days=7)
    return rows


def render_table(schedule):
    """Render a schedule as a fixed-width text table."""
    lines = ["week-start  on-call", "----------- -------"]
    for row in schedule:
        lines.append("%s  %s" % (row["week_start"], row["member_id"]))
    return "\n".join(lines) + "\n"