"""Regression suite for the coursebook registration model.

These tests pin two behaviours: the public contract of ``coursebook.store``,
and the schema-level registration invariant documented in README.md -- a
student holds at most one registration row per course, in one of the statuses
active / completed / dropped.

The last test is deliberately SQL-level: the UNIQUE constraint must hold in
the schema itself, not only in the Python API, so that a writer which
bypasses this module cannot create a duplicate row.
"""

import sqlite3

import pytest

import coursebook.db as db
import coursebook.store as store
from coursebook.errors import (
    DuplicateRegistrationError,
    InvalidStateError,
    NoRegistrationError,
)


@pytest.fixture
def conn():
    c = db.connect(":memory:")
    db.init_db(c)
    yield c
    c.close()


@pytest.fixture
def seeded(conn):
    store.add_student(conn, "ada@example.org", "Ada Lovelace")
    store.add_student(conn, "alan@example.org", "Alan Turing")
    store.add_course(conn, "CS101", "Intro to Computing", 2)
    store.add_course(conn, "MATH201", "Linear Algebra", 2)
    return conn


def test_register_creates_an_active_registration(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    rows = store.history(seeded, "ada@example.org")
    assert len(rows) == 1
    assert rows[0] == ("CS101", "Intro to Computing", "2024F", "active", "")


def test_duplicate_registration_raises(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    with pytest.raises(DuplicateRegistrationError):
        store.register(seeded, "ada@example.org", "CS101", "2025S")


def test_duplicate_registration_raises_after_completion(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    store.complete(seeded, "ada@example.org", "CS101", "B")
    with pytest.raises(DuplicateRegistrationError):
        store.register(seeded, "ada@example.org", "CS101", "2025S")


def test_register_for_different_courses(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    store.register(seeded, "ada@example.org", "MATH201", "2024F")
    assert len(store.history(seeded, "ada@example.org")) == 2


def test_schema_forbids_duplicate_rows_even_with_raw_sql(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    sid = seeded.execute(
        "SELECT id FROM students WHERE email = 'ada@example.org'"
    ).fetchone()[0]
    cid = seeded.execute(
        "SELECT id FROM courses WHERE code = 'CS101'"
    ).fetchone()[0]
    with pytest.raises(sqlite3.IntegrityError):
        seeded.execute(
            "INSERT INTO registrations (student_id, course_id, semester, status)"
            " VALUES (?, ?, '2025S', 'active')",
            (sid, cid),
        )


def test_roster_lists_each_student_once(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    store.register(seeded, "alan@example.org", "CS101", "2024F")
    roster = store.roster(seeded, "CS101")
    emails = [r[0] for r in roster]
    assert emails == ["ada@example.org", "alan@example.org"]
    assert len(emails) == len(set(emails))


def test_roster_reflects_completion(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    store.register(seeded, "alan@example.org", "CS101", "2024F")
    store.complete(seeded, "ada@example.org", "CS101", "A")
    roster = dict((r[0], r[2]) for r in store.roster(seeded, "CS101"))
    assert roster["ada@example.org"] == "completed"
    assert roster["alan@example.org"] == "active"


def test_seat_usage_counts_active_registrations(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    store.register(seeded, "alan@example.org", "CS101", "2024F")
    usage = dict((r[0], r[3]) for r in store.seat_usage(seeded))
    assert usage["CS101"] == 2


def test_seat_usage_ignores_completed_and_dropped(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    store.complete(seeded, "ada@example.org", "CS101", "A")
    store.register(seeded, "alan@example.org", "CS101", "2024F")
    store.withdraw(seeded, "alan@example.org", "CS101")
    usage = dict((r[0], r[3]) for r in store.seat_usage(seeded))
    assert usage["CS101"] == 0


def test_complete_records_grade_and_status(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    store.complete(seeded, "ada@example.org", "CS101", "B+")
    rows = store.history(seeded, "ada@example.org")
    assert rows[0][3] == "completed"
    assert rows[0][4] == "B+"


def test_complete_requires_an_active_registration(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    store.complete(seeded, "ada@example.org", "CS101", "A")
    with pytest.raises(InvalidStateError):
        store.complete(seeded, "ada@example.org", "CS101", "B")


def test_complete_without_registration_raises(seeded):
    with pytest.raises(NoRegistrationError):
        store.complete(seeded, "ada@example.org", "CS101", "A")


def test_withdraw_changes_status(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    store.withdraw(seeded, "ada@example.org", "CS101")
    rows = store.history(seeded, "ada@example.org")
    assert rows[0][3] == "dropped"


def test_withdraw_requires_active(seeded):
    store.register(seeded, "ada@example.org", "CS101", "2024F")
    store.complete(seeded, "ada@example.org", "CS101", "A")
    with pytest.raises(InvalidStateError):
        store.withdraw(seeded, "ada@example.org", "CS101")


def test_add_course_rejects_nonpositive_seats(conn):
    with pytest.raises(ValueError):
        store.add_course(conn, "PHY101", "Physics", 0)