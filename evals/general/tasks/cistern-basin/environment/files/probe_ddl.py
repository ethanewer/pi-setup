#!/usr/bin/env python3
"""Probe for the SQLite table-options DDL bug.

Builds a Table that uses both SQLite dialect table options at once --
sqlite_with_rowid=False (no rowid storage) and sqlite_strict=True (strict
table mode) -- prints the CREATE TABLE statement the dialect generates, and
tries to execute it against an in-memory SQLite database.

Fixed behaviour (expected):

    CREATE TABLE atable (
        id INTEGER NOT NULL,
        PRIMARY KEY (id)
    )
     WITHOUT ROWID,
     STRICT
    EXECUTED OK; tables: ['atable']

Buggy behaviour observed at the pinned commit: the two extension clauses are
emitted with no comma between them and executing the resulting DDL raises

    sqlite3.OperationalError: near "STRICT": syntax error
"""

import sys

from sqlalchemy import Column, Integer, MetaData, Table, create_engine
from sqlalchemy.dialects import sqlite as sqlite_dialect
from sqlalchemy.schema import CreateTable


def main() -> int:
    m = MetaData()
    t = Table(
        "atable",
        m,
        Column("id", Integer, primary_key=True),
        sqlite_with_rowid=False,
        sqlite_strict=True,
    )
    ddl = str(CreateTable(t).compile(dialect=sqlite_dialect.dialect()))
    print(ddl)
    engine = create_engine("sqlite://")
    with engine.begin() as conn:
        conn.exec_driver_sql(ddl)
        names = conn.exec_driver_sql(
            "SELECT name FROM sqlite_master WHERE type = 'table'"
        ).all()
    print("EXECUTED OK; tables:", [r[0] for r in names])
    return 0


if __name__ == "__main__":
    sys.exit(main())