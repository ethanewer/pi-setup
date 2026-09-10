"""Retake enrolments for coursebook.

Retakes are additional enrolment events for a student who already holds a
registration row in a course.  They are stored OUTSIDE ``registrations``, in
their own table, so the registration invariant documented in README.md (at
most one registration row per student and course) is preserved: rosters,
seat usage, grading and history keep their exact meaning.

This module is the implementing half of the objection filed for Request 42:
the request's proposed change (dropping UNIQUE(student_id, course_id) and
recording retakes as duplicate registration rows) would have made a single
seat consume double, a student appear twice on a roster, and a grade
ambiguous.  Instead, a retake is a first-class event linked to the existing
(unique) registration row.
"""

import sqlite3

from .errors import (
    DuplicateRegistrationError,
    NoRegistrationError,
    NotFoundError,
)

DDL = """
CREATE TABLE IF NOT EXISTS retakes (
    id INTEGER PRIMARY KEY,
    registration_id INTEGER NOT NULL REFERENCES registrations(id),
    semester TEXT NOT NULL,
    UNIQUE (registration_id, semester)
);
"""


def ensure_table(conn: sqlite3.Connection) -> None:
    """Create the retakes table if it does not exist (idempotent)."""
    conn.execute(DDL)
    conn.commit()


def _registration_row(conn, email, code):
    row = conn.execute(
        """
        SELECT r.id AS id
        FROM registrations r
        JOIN students s ON s.id = r.student_id
        JOIN courses c ON c.id = r.course_id
        WHERE s.email = ? AND c.code = ?
        """,
        (email, code),
    ).fetchone()
    return row


def retake(conn: sqlite3.Connection, email: str, code: str, semester: str) -> None:
    """Record one retake enrolment for ``email`` in ``code``.

    Requires an existing registration row for the student and course (any
    status).  Fails with NoRegistrationError if there is none, and with
    DuplicateRegistrationError if this exact (course, semester) retake has
    already been recorded.  Never touches ``registrations``.
    """
    reg = _registration_row(conn, email, code)
    if reg is None:
        raise NoRegistrationError(
            f"{email} has no registration for {code}; a retake requires a"
            " prior registration"
        )
    dup = conn.execute(
        "SELECT id FROM retakes WHERE registration_id = ? AND semester = ?",
        (reg["id"], semester),
    ).fetchone()
    if dup is not None:
        raise DuplicateRegistrationError(
            f"{email} already has a retake for {code} in {semester}"
        )
    with conn:
        conn.execute(
            "INSERT INTO retakes (registration_id, semester) VALUES (?, ?)",
            (reg["id"], semester),
        )


def attempts(conn: sqlite3.Connection, email: str):
    """Rows ``(event, code, title, semester)`` for every enrolment event of
    one student: the registration row per course, then its retakes in the
    order they were recorded, ordered by course code."""
    if conn.execute(
        "SELECT id FROM students WHERE email = ?", (email,)
    ).fetchone() is None:
        raise NotFoundError(f"no student with email {email!r}")
    regs = conn.execute(
        """
        SELECT c.code AS code, c.title AS title, r.semester AS semester
        FROM registrations r
        JOIN students s ON s.id = r.student_id
        JOIN courses c ON c.id = r.course_id
        WHERE s.email = ?
        ORDER BY c.code
        """,
        (email,),
    ).fetchall()
    rows = []
    for reg in regs:
        rows.append(("registration", reg["code"], reg["title"], reg["semester"]))
        retakes = conn.execute(
            """
            SELECT k.semester AS semester
            FROM retakes k
            JOIN registrations r ON r.id = k.registration_id
            WHERE r.id = (
                SELECT r2.id
                FROM registrations r2
                JOIN students s ON s.id = r2.student_id
                JOIN courses c ON c.id = r2.course_id
                WHERE s.email = ? AND c.code = ?
            )
            ORDER BY k.id
            """,
            (email, reg["code"]),
        ).fetchall()
        for k in retakes:
            rows.append(("retake", reg["code"], reg["title"], k["semester"]))
    return rows