"""Rotation wheel.

[MUTANT] This build is the "stuck wheel": the member who carried the
previous cycle is handed the next one every time, so the rotation never
advances.  The rest of the module API is unchanged.
"""
from __future__ import annotations

from datetime import datetime


def _parse_ts(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def availability(member, now=None):
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


def pick(team, previous=None, now=None):
    if not team:
        raise ValueError("cannot rotate an empty roster")
    # MUTANT: the wheel never advances; the previous member is always
    # returned, so consecutive cycles land on the same person.
    if previous is not None:
        return previous
    return team[0]