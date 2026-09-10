"""Domain operations for coursebook.

Every operation in this module relies on the registration invariant: a
student holds at most one registration row per course, in one of three
statuses (active / completed / dropped).  The invariant is enforced both
here, by the Python API, and by the schema's ``UNIQUE (student_id,
course_id)`` constraint, which rejects a duplicate row even for a writer
that bypasses this module.
"""

import sqlite3

from .errors import (
    DuplicateRegistrationError,
    InvalidStateError,
    NotFoundError,
    NoRegistrationError,
)

ACTIVE = "active"
COMPLETED = "completed"
DROPPED = "dropped"


def _student_id(conn, email):
    row = conn.execute(
        "SELECT id FROM students WHERE email = ?", (email,)
    ).fetchone()
    if row is None:
        raise NotFoundError(f"no student with email {email!r}")
    return row["id"]


def _course_id(conn, code):
    row = conn.execute(
        "SELECT id FROM courses WHERE code = ?", (code,)
    ).fetchone()
    if row is None:
        raise NotFoundError(f"no course with code {code!r}")
    return row["id"]


def _registration(conn, student_id, course_id):
    return conn.execute(
        "SELECT * FROM registrations WHERE student_id = ? AND course_id = ?",
        (student_id, course_id),
    ).fetchone()


def add_student(conn, email: str, name: str) -> int:
    try:
        with conn:
            cur = conn.execute(
                "INSERT INTO students (email, name) VALUES (?, ?)",
                (email, name),
            )
            return cur.lastrowid
    except sqlite3.IntegrityError as exc:
        raise NotFoundError(
            f"a student with email {email!r} already exists"
        ) from exc


def add_course(conn, code: str, title: str, seats: int) -> int:
    if seats <= 0:
        raise ValueError("seats must be a positive integer")
    try:
        with conn:
            cur = conn.execute(
                "INSERT INTO courses (code, title, seats) VALUES (?, ?, ?)",
                (code, title, seats),
            )
            return cur.lastrowid
    except sqlite3.IntegrityError as exc:
        raise NotFoundError(f"a course with code {code!r} already exists") from exc


def register(conn, email: str, code: str, semester: str) -> int:
    """Register ``email`` for ``code``, raising DuplicateRegistrationError
    if the student already holds a registration row for that course."""
    sid = _student_id(conn, email)
    cid = _course_id(conn, code)
    if _registration(conn, sid, cid) is not None:
        raise DuplicateRegistrationError(
            f"{email} is already registered for {code}"
        )
    with conn:
        cur = conn.execute(
            "INSERT INTO registrations (student_id, course_id, semester, status)"
            " VALUES (?, ?, ?, 'active')",
            (sid, cid, semester),
        )
        return cur.lastrowid


def complete(conn, email: str, code: str, grade: str) -> None:
    """Mark an active registration completed and record its grade."""
    sid = _student_id(conn, email)
    cid = _course_id(conn, code)
    row = _registration(conn, sid, cid)
    if row is None:
        raise NoRegistrationError(f"{email} has no registration for {code}")
    if row["status"] != ACTIVE:
        raise InvalidStateError(
            f"registration of {email} for {code} is {row['status']}, not active"
        )
    with conn:
        conn.execute(
            "UPDATE registrations SET status = 'completed', grade = ?"
            " WHERE id = ?",
            (grade, row["id"]),
        )


def withdraw(conn, email: str, code: str) -> None:
    """Drop an active registration for ``email`` in ``code``."""
    sid = _student_id(conn, email)
    cid = _course_id(conn, code)
    row = _registration(conn, sid, cid)
    if row is None:
        raise NoRegistrationError(f"{email} has no registration for {code}")
    if row["status"] != ACTIVE:
        raise InvalidStateError(
            f"registration of {email} for {code} is {row['status']}, not active"
        )
    with conn:
        conn.execute(
            "UPDATE registrations SET status = 'dropped' WHERE id = ?",
            (row["id"],),
        )


def roster(conn, code: str):
    """Rows ``(email, name, status)`` for ``code``, one per student, by
    email. A student appears at most once because of the invariant."""
    _course_id(conn, code)
    rows = conn.execute(
        """
        SELECT s.email AS email, s.name AS name, r.status AS status
        FROM registrations r
        JOIN students s ON s.id = r.student_id
        WHERE r.course_id = (SELECT id FROM courses WHERE code = ?)
        ORDER BY s.email
        """,
        (code,),
    ).fetchall()
    return [tuple(r) for r in rows]


def seat_usage(conn):
    """Rows ``(code, title, seats, registered)`` per course by code.
    ``registered`` counts only status = 'active'."""
    rows = conn.execute(
        """
        SELECT c.code AS code, c.title AS title, c.seats AS seats,
               COUNT(CASE WHEN r.status = 'active' THEN 1 END) AS registered
        FROM courses c
        LEFT JOIN registrations r ON r.course_id = c.id
        GROUP BY c.id
        ORDER BY c.code
        """
    ).fetchall()
    return [tuple(r) for r in rows]


def history(conn, email: str):
    """Rows ``(code, title, semester, status, grade)`` for one student's
    registrations, one row per course, by course code. Grade is '' when
    none has been recorded."""
    _student_id(conn, email)
    rows = conn.execute(
        """
        SELECT c.code AS code, c.title AS title, r.semester AS semester,
               r.status AS status, IFNULL(r.grade, '') AS grade
        FROM registrations r
        JOIN courses c ON c.id = r.course_id
        WHERE r.student_id = (SELECT id FROM students WHERE email = ?)
        ORDER BY c.code
        """,
        (email,),
    ).fetchall()
    return [tuple(r) for r in rows]