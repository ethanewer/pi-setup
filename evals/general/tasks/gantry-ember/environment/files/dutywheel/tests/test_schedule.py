"""Weekly schedule rendering tests."""
import datetime

import dutywheel.schedule as schedule

START = datetime.date(2026, 11, 2)
NOW = datetime.datetime(2026, 11, 2, 9, 0, 0, tzinfo=datetime.timezone.utc)


def test_schedule_has_four_weeks(roster):
    rows = schedule.build_weeks(roster, START, weeks=4, now=NOW)
    assert len(rows) == 4


def test_weeks_advance_by_seven_days(roster):
    rows = schedule.build_weeks(roster, START, weeks=4, now=NOW)
    prev = datetime.date.fromisoformat(rows[0]["week_start"])
    for row in rows[1:]:
        current = datetime.date.fromisoformat(row["week_start"])
        assert (current - prev).days == 7
        prev = current


def test_every_week_names_a_known_member(roster):
    known = {m["id"] for m in roster["members"]}
    rows = schedule.build_weeks(roster, START, weeks=4, now=NOW)
    assert {r["member_id"] for r in rows} <= known


def test_rendered_table_has_header_and_one_row_per_week(roster):
    rows = schedule.build_weeks(roster, START, weeks=2, now=NOW)
    text = schedule.render_table(rows)
    lines = text.strip().splitlines()
    assert lines[0].startswith("week-start")
    assert len(lines) == 2 + 2


def test_schedule_rejects_zero_weeks(roster):
    import pytest
    with pytest.raises(ValueError):
        schedule.build_weeks(roster, START, weeks=0, now=NOW)