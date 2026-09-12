"""End-to-end hidden cases: the combined table options must produce DDL that
actually executes against SQLite and creates the table.

The project's upstream regression test only checks the compiled string.  These
cases execute the emitted DDL against an in-memory SQLite database and verify
the table really exists with both extension clauses present in the stored DDL.
"""

import re

from sqlalchemy import Column, Integer, MetaData, Table, create_engine, inspect


def _norm(sql):
    return re.sub(r"\s+", " ", sql.replace("\t", " ")).strip()


def test_combined_options_table_creates_and_roundtrips():
    engine = create_engine("sqlite:///:memory:")
    m = MetaData()
    t = Table(
        "gadgets",
        m,
        Column("id", Integer, primary_key=True),
        sqlite_with_rowid=False,
        sqlite_strict=True,
    )

    # At the parent commit this raises
    # sqlite3.OperationalError: near "STRICT": syntax error.
    t.create(engine)

    with engine.connect() as conn:
        ddl = conn.exec_driver_sql(
            "SELECT sql FROM sqlite_master WHERE type = 'table' "
            "AND name = 'gadgets'"
        ).scalar()
        cols = conn.exec_driver_sql("PRAGMA table_info(gadgets)").all()

    assert ddl is not None
    assert "WITHOUT ROWID, STRICT" in _norm(ddl)
    assert "WITHOUT ROWID STRICT" not in _norm(ddl)
    assert [c[1] for c in cols] == ["id"]


def test_multiple_tables_created_together_and_reflectable():
    engine = create_engine("sqlite:///:memory:")
    m = MetaData()
    a = Table(
        "alpha",
        m,
        Column("id", Integer, primary_key=True),
        sqlite_with_rowid=False,
        sqlite_strict=True,
    )
    b = Table(
        "beta",
        m,
        Column("id", Integer, primary_key=True),
        sqlite_with_rowid=False,
    )
    c = Table(
        "gamma",
        m,
        Column("id", Integer, primary_key=True),
        sqlite_strict=True,
    )

    # create_all emits one DDL statement per table; the "alpha" statement
    # alone must not stop the batch at the parent commit.
    m.create_all(engine)

    with engine.connect() as conn:
        rows = conn.exec_driver_sql(
            "SELECT name, sql FROM sqlite_master WHERE type = 'table' "
            "ORDER BY name"
        ).all()
        stored = {name: _norm(sql) for name, sql in rows}

    assert "WITHOUT ROWID, STRICT" in stored["alpha"]
    assert stored["beta"].endswith("WITHOUT ROWID")
    assert stored["gamma"].endswith("STRICT")

    # reflection sees all three tables
    assert sorted(inspect(engine).get_table_names()) == ["alpha", "beta", "gamma"]