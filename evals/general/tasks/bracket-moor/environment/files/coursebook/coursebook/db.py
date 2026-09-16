"""SQLite schema and connection helpers.

This module is the single source of truth for the storage layout.  The
load-bearing part of the schema is the ``UNIQUE (student_id, course_id)``
constraint on ``registrations`` -- see README.md, "The registration
invariant".  Every other table and view in the system derives its meaning
from the fact that a student holds at most one registration row per course.
"""

import sqlite3

SCHEMA = """
CREATE TABLE IF NOT EXISTS students (
    id INTEGER PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS courses (
    id INTEGER PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    seats INTEGER NOT NULL CHECK (seats > 0)
);

CREATE TABLE IF NOT EXISTS registrations (
    id INTEGER PRIMARY KEY,
    student_id INTEGER NOT NULL REFERENCES students(id),
    course_id INTEGER NOT NULL REFERENCES courses(id),
    semester TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'completed', 'dropped')),
    grade TEXT,
    UNIQUE (student_id, course_id)
);
"""


def connect(path: str) -> sqlite3.Connection:
    """Open a connection at ``path`` with row access and foreign keys on."""
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db(conn: sqlite3.Connection) -> None:
    """Create every table in SCHEMA (idempotent)."""
    conn.executescript(SCHEMA)
    conn.commit()