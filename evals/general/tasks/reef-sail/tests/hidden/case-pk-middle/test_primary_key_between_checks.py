"""Hidden case: a bare PRIMARY KEY clause physically sitting between two
CHECK constraints, with CHECK expressions containing string literals.

The upstream regression test for this bug uses a NAMED PRIMARY KEY clause
(emitted by SQLAlchemy as 'CONSTRAINT pk_name PRIMARY KEY (id)', which the
old reflection splitter already handled) and bare expressions without
string literals.

SQLAlchemy itself never emits an unnamed PRIMARY KEY in the middle of a
CREATE TABLE (it hoists it first), but real databases created by hand or
by other tools do.  Here the table is created from raw DDL, so the stored
CREATE TABLE text physically interleaves: CHECK, PRIMARY KEY, CHECK,
UNIQUE.  Reflection must return both CHECK expressions pure (a comma inside
a quoted string literal is not a constraint boundary) and the PRIMARY KEY
and UNIQUE must still reflect with their columns.
"""

from sqlalchemy import create_engine, inspect

RAW_DDL = """
CREATE TABLE orders (
    id INTEGER,
    token VARCHAR(48),
    status VARCHAR(12),
    CONSTRAINT ck_status_values CHECK (status IN ('open', 'closed', 'on-hold')),
    PRIMARY KEY (id),
    CONSTRAINT ck_token_len CHECK (length(token) >= 8),
    UNIQUE (token)
)
"""


def _reflected():
    engine = create_engine("sqlite:///:memory:")
    with engine.begin() as conn:
        conn.exec_driver_sql(RAW_DDL)
        insp = inspect(conn)
        checks = {c["name"]: c["sqltext"] for c in insp.get_check_constraints("orders")}
        pk = insp.get_pk_constraint("orders")
        uniques = [u["column_names"] for u in insp.get_unique_constraints("orders")]
    return checks, pk, uniques


def test_check_before_bare_primary_key_is_pure():
    checks, _, _ = _reflected()
    assert checks["ck_status_values"] == "status IN ('open', 'closed', 'on-hold')", (
        checks["ck_status_values"]
    )


def test_check_after_bare_primary_key_is_pure():
    checks, _, _ = _reflected()
    assert checks["ck_token_len"] == "length(token) >= 8", checks["ck_token_len"]


def test_no_primary_key_text_leaks_into_check_sqltext():
    checks, _, _ = _reflected()
    for sqltext in checks.values():
        assert "PRIMARY" not in sqltext.upper(), sqltext
        assert "KEY" not in sqltext.upper(), sqltext


def test_primary_key_and_unique_still_reflect():
    _, pk, uniques = _reflected()
    assert pk["name"] is None, pk
    assert pk["constrained_columns"] == ["id"], pk
    assert ["token"] in uniques, uniques