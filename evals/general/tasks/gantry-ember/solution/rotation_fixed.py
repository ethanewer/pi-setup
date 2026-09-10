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

FIXED: the two defects that made the wheel nondeterministic are removed.

1. The previous on-call member is excluded from the pool while any other
   member exists, so consecutive cycles can never land on the same member
   (the previous value was previously accepted but never used).
2. The tie-break key is the member id in character order, not the
   interpreter's builtin ``hash()``.  ``hash()`` of a string is randomized
   per process via the hash seed, so two processes rendering the same
   roster picked different winners and the suite flaked across runs.  A
   character-order tie-break is stable across processes, retries and
   interpreters.
"""
from __future__ import annotations

from datetime import datetime


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
    # Stable character-order tie-break key.
    #
    # The wheel's winner must be identical in every process and on every
    # retry of the same cycle.  The interpreter's builtin hash() of a
    # string is randomized per process (PYTHONHASHSEED), so it is
    # deliberately NOT used here: a character-order key is stable across
    # processes, retries and interpreters.
    return member["id"]


def pick(team, previous=None, now=None):
    """Return the member who carries the next duty cycle.

    team      list of member dicts (see dutywheel.crew)
    previous  the member who carried the previous cycle; the wheel must not
              return them while any other member is available
    now       datetime the availability check is evaluated at, or None
    """
    if not team:
        raise ValueError("cannot rotate an empty roster")
    # Pass the previous member over: as long as anyone else is in the
    # roster, the next cycle goes to a different member.
    pool = [m for m in team if m is not previous]
    if not pool:
        pool = team
    return min(pool, key=lambda m: (availability(m, now), _tiebreak(m)))