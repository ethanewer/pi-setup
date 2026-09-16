"""Hidden case: a CHECK constraint followed by an unnamed FOREIGN KEY clause.

The upstream regression test for this bug never declares a FOREIGN KEY next
to a CHECK, so the 'FOREIGN KEY(...)' clause boundary is not exercised
there.  Here a CHECK constraint is directly followed by an unnamed
ForeignKeyConstraint (emitted as a bare 'FOREIGN KEY(...) REFERENCES ...'
clause) and then by a second CHECK and an unnamed UNIQUE.  Reflection must
return both CHECK expressions pure (no appended ', FOREIGN KEY(...)
REFERENCES ...' text) and the foreign key itself must still reflect with
its constrained columns, referred schema/table/columns, and name None.
"""

from sqlalchemy import (
    CheckConstraint,
    Column,
    ForeignKeyConstraint,
    Integer,
    MetaData,
    Table,
    UniqueConstraint,
    create_engine,
    inspect,
)


def _reflected():
    engine = create_engine("sqlite:///:memory:")
    m = MetaData()
    Table("parent", m, Column("id", Integer, primary_key=True))
    Table(
        "line_item",
        m,
        Column("id", Integer, primary_key=True),
        Column("parent_id", Integer),
        Column("amount", Integer),
        CheckConstraint("amount > 0", name="ck_amount_positive"),
        ForeignKeyConstraint(["parent_id"], ["parent.id"]),
        CheckConstraint("amount < 1000000", name="ck_amount_cap"),
        UniqueConstraint("amount"),
    )
    m.create_all(engine)
    with engine.connect() as conn:
        insp = inspect(conn)
        checks = {c["name"]: c["sqltext"] for c in insp.get_check_constraints("line_item")}
        fks = insp.get_foreign_keys("line_item")
    return checks, fks


def test_check_before_fk_is_pure():
    checks, _ = _reflected()
    assert checks["ck_amount_positive"] == "amount > 0", checks["ck_amount_positive"]


def test_check_after_fk_is_pure():
    checks, _ = _reflected()
    assert checks["ck_amount_cap"] == "amount < 1000000", checks["ck_amount_cap"]


def test_no_fk_text_leaks_into_check_sqltext():
    checks, _ = _reflected()
    for sqltext in checks.values():
        assert "FOREIGN" not in sqltext.upper(), sqltext
        assert "REFERENCES" not in sqltext.upper(), sqltext


def test_foreign_key_still_reflects_fully():
    _, fks = _reflected()
    assert len(fks) == 1, fks
    fk = fks[0]
    assert fk["name"] is None, fk
    assert fk["constrained_columns"] == ["parent_id"], fk
    assert fk["referred_table"] == "parent", fk
    assert fk["referred_columns"] == ["id"], fk