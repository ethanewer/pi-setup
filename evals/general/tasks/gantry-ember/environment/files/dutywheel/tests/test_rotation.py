"""Rotation wheel contract tests.

The contract under test: the member who carried the previous duty cycle is
never handed the next cycle while any other member is available, and the
wheel's selection is reproducible for the same roster snapshot.
"""
import datetime

import pytest

import dutywheel.rotation as rotation

# A Monday morning inside no maintenance window of the shipped roster.
# Aware UTC to match the roster window timestamps.
NOW = datetime.datetime(2026, 11, 2, 9, 0, 0, tzinfo=datetime.timezone.utc)


def test_pick_returns_a_member_of_the_team(roster):
    team = roster["members"]
    picked = rotation.pick(team, now=NOW)
    assert any(m["id"] == picked["id"] for m in team)


def test_pick_rejects_an_empty_roster():
    with pytest.raises(ValueError):
        rotation.pick([], now=NOW)


def test_availability_ignores_expired_windows(roster):
    # every window shipped in the sample roster is in the past, so the
    # whole crew is fully available at NOW
    for member in roster["members"]:
        assert rotation.availability(member, NOW) == 0


def test_availability_counts_overlapping_windows():
    member = {
        "id": "bob",
        "name": "Bob",
        "role": "primary",
        "windows": [
            {"start": "2026-11-02T08:00:00Z", "end": "2026-11-02T10:00:00Z"},
        ],
    }
    assert rotation.availability(member, NOW) == 1
    assert rotation.availability(member, NOW - datetime.timedelta(hours=3)) == 0


def test_wheel_moves_past_the_previous_member(roster):
    """Consecutive duty cycles never land on the same member.

    The roster at NOW has every member fully available, so the wheel must
    simply hand the cycle to someone other than the previous on-call.
    """
    team = roster["members"]
    previous = team[0]
    picked = rotation.pick(team, previous=previous, now=NOW)
    assert picked["id"] != previous["id"]