"""Hidden case: a CHECK constraint followed by an unnamed multi-column
UNIQUE, then by another CHECK, plus a named UNIQUE elsewhere.

The upstream regression test for this bug (ConstraintReflectionTest::test_
check_constraint in the fix revision) uses a single-column UNNAMED unique
after its multiline CHECK.  These cases exercise the same reflection code
path from inputs the upstream test does not use: a two-column named UNIQUE
emitted as CONSTRAINT ... UNIQUE, a two-column UNNAMED UNIQUE emitted as a
bare UNIQUE (...), a compound CHECK expression, and a trailing CHECK.  The
reflected CHECK sqltext must be exactly the pure expression (no trailing
comma, no swallowed 'UNIQUE (...)' text) and every UNIQUE constraint must
still reflect with its full column list.
"""

from sqlalchemy import (
    CheckConstraint,
    Column,
    Integer,
    MetaData,
    String,
    Table,
    UniqueConstraint,
    create_engine,
    inspect,
)


def _reflected():
    engine = create_engine("sqlite:///:memory:")
    m = MetaData()
    Table(
        "stock",
        m,
        Column("sku", String(32)),
        Column("warehouse", String(16)),
        Column("qty", Integer),
        Column("price", Integer),
        CheckConstraint("price > 0 AND price < 1000", name="ck_price"),
        UniqueConstraint("sku", "warehouse"),
        CheckConstraint("qty >= 0", name="ck_qty"),
        UniqueConstraint("qty", name="uq_qty"),
    )
    m.create_all(engine)
    with engine.connect() as conn:
        insp = inspect(conn)
        checks = {c["name"]: c["sqltext"] for c in insp.get_check_constraints("stock")}
        uniques = {tuple(u["column_names"]): u["name"] for u in insp.get_unique_constraints("stock")}
    return checks, uniques


def test_check_before_unnamed_unique_is_pure():
    checks, _ = _reflected()
    assert checks["ck_price"] == "price > 0 AND price < 1000", checks["ck_price"]


def test_check_after_unnamed_unique_is_pure():
    checks, _ = _reflected()
    assert checks["ck_qty"] == "qty >= 0", checks["ck_qty"]


def test_no_trailing_clause_text_appended():
    checks, _ = _reflected()
    for sqltext in checks.values():
        assert "UNIQUE" not in sqltext.upper(), sqltext
        assert not sqltext.rstrip().endswith(","), sqltext


def test_multicolumn_unique_still_reflects():
    _, uniques = _reflected()
    # the unnamed UNIQUE (sku, warehouse) and the named UNIQUE (qty)
    assert uniques.get(("sku", "warehouse")) is None, uniques
    assert uniques.get(("qty",)) == "uq_qty", uniques


def test_constraint_counts_are_complete():
    checks, uniques = _reflected()
    assert set(checks) == {"ck_price", "ck_qty"}
    assert len(uniques) == 2, uniques