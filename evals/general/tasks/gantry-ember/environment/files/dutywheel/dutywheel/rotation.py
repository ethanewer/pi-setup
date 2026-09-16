"""Rotation wheel.

``pick(team, previous=None, now=None)`` chooses the member who carries the
next duty cycle:

* availability first: a member with an overlapping maintenance window at
  ``now`` is skipped unless nobody else is available;
* among equally available members the winner must be stable: the same
  roster snapshot must always pick the same member, in every process and
  on every retry of the same cycle;
* the member who carried the previous cycle is never handed the next one
  while any other member is available.
"""
from __future__ import annotations

from datetime import datetime, timedelta


def _parse_ts(value):
    # ISO-8601 UTC timestamp, e.g. "2026-11-02T09:00:00Z"
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def availability(member, now=None):
    """Number of maintenance windows of *member* overlapping *now*.

    0 means fully available.  With ``now=None`` no window is evaluated, so
    every member ties on availability.
    """
    if now is None:
        return 0
    overlap = 0
    for win in member["windows"]:
        if not isinstance(win, dict):
            continue
        start = _parse_ts(win["start"]) if "start" in win else None
        end = _parse_ts(win["end"]) if "end" in win else None
        if start is not None and end is not None and start <= now < end:
            overlap += 1
    return overlap


def _tiebreak(member):
    # Tie-break key for equally available members.
    #
    # We deliberately do NOT use the display name: names are edited freely
    # in the roster and the wheel's assignment must not jump when a name
    # changes.  The interpreter's builtin hash() of the member id is stable
    # for the lifetime of one process, which keeps the assignment
    # reproducible across retries of the same cycle.
    return hash(member["id"])


def pick(team, previous=None, now=None):
    """Return the member who carries the next duty cycle.

    team      list of member dicts (see dutywheel.crew)
    previous  the member who carried the previous cycle; the wheel must not
              return them while any other member is available
    now       datetime the availability check is evaluated at, or None
    """
    if not team:
        raise ValueError("cannot rotate an empty roster")
    return min(team, key=lambda m: (availability(m, now), _tiebreak(m)))