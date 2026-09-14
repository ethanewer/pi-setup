#!/usr/bin/env python3
"""Reproduction of the SQLite CHECK-constraint reflection corruption
(reef-sail deliverable).

Creates an in-memory SQLite database whose CREATE TABLE interleaves CHECK
constraints with UNIQUE / PRIMARY KEY clauses, reflects the constraints, and
requires every CHECK constraint to come back with its exact, pure check
expression.  Exits 0 when reflection is clean; prints the corruption and
exits 1 otherwise.

The table mirrors what a real application would store:

    CHECK (id > 0), UNIQUE (prefix), CHECK (multiline expression),
    UNIQUE (value), CHECK (value IS NOT NULL), PRIMARY KEY (id),
    CHECK (prefix NOT GLOB ...)

The UNIQUE / PRIMARY KEY constraints are intentionally declared WITHOUT
names so SQLAlchemy emits them as bare clauses (`UNIQUE (...)`,
`PRIMARY KEY (id)`); with explicit names they would be emitted as
`CONSTRAINT <name> UNIQUE (...)` and the corruption would not appear.
"""

import sys

from sqlalchemy import (
    CheckConstraint,
    Column,
    Integer,
    MetaData,
    PrimaryKeyConstraint,
    String,
    Table,
    UniqueConstraint,
    create_engine,
    inspect,
)

# name -> exact pure expression expected on reflection
EXPECTED = {
    "ck_id_positive": "id > 0",
    "ck_r_value_multiline": (
        "((value > 0) AND \n\t(value < 100) AND \n\t(value != 50))"
    ),
    "check-constrained": "value IS NOT NULL",
    "ck_prefix_charset": "prefix NOT GLOB '*[^-. /#,]*'",
}


def build():
    m = MetaData()
    Table(
        "r",
        m,
        Column("id", Integer),
        Column("value", Integer),
        Column("prefix", String),
        CheckConstraint("id > 0", name="ck_id_positive"),
        UniqueConstraint("prefix"),
        CheckConstraint(
            "((value > 0) AND \n\t(value < 100) AND \n\t(value != 50))",
            name="ck_r_value_multiline",
        ),
        UniqueConstraint("value"),
        CheckConstraint("value IS NOT NULL", name="check-constrained"),
        PrimaryKeyConstraint("id"),
        CheckConstraint("prefix NOT GLOB '*[^-. /#,]*'", name="ck_prefix_charset"),
    )
    engine = create_engine("sqlite://")
    with engine.begin() as conn:
        m.create_all(conn)
        reflected = inspect(conn).get_check_constraints("r")
    return reflected


def main() -> int:
    reflected = build()
    print("reflected check constraints:")
    by_name = {}
    for entry in reflected:
        by_name[entry["name"]] = entry["sqltext"]
        print("  %r: %r" % (entry["name"], entry["sqltext"]))

    problems = []
    for name, expected in EXPECTED.items():
        if name not in by_name:
            problems.append("missing check constraint %r" % name)
        elif by_name[name] != expected:
            problems.append(
                "check %r corrupted:\n  expected %r\n  observed %r"
                % (name, expected, by_name[name])
            )
    if problems:
        print("CORRUPTED: " + "; ".join(problems))
        return 1
    print("ALL CHECK CONSTRAINTS REFLECT CLEANLY")
    return 0


if __name__ == "__main__":
    sys.exit(main())