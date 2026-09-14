"""Hidden case 2: DELETE .. RETURNING with scrambled returning order and THREE
consecutive executions (one cache miss, two cache hits), plus a row-count
check that the rows really were deleted."""
from sqlalchemy import create_engine, delete, Integer, select, func
from sqlalchemy.orm import Session, DeclarativeBase, mapped_column, Mapped


class Base(DeclarativeBase):
    pass


class T(Base):
    __tablename__ = "tdel"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    b: Mapped[int] = mapped_column(Integer)
    a: Mapped[int] = mapped_column(Integer)


def test_h2_three_hits():
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    with engine.begin() as c:
        c.execute(
            T.__table__.insert(),
            [dict(id=i, a=i * 10, b=i * 100) for i in range(1, 7)],
        )
    opts = {"synchronize_session": "fetch"}
    for n, ident in enumerate((2, 4, 6), 1):
        stmt = delete(T).where(T.id == ident).returning(T.b, T.a, T.id)
        with Session(engine) as sess:
            res = sess.execute(stmt, execution_options=opts)
            raw = res.raw
            meta = raw._metadata
            tc = T.__table__.c
            for col, name in ((tc.b, "b"), (tc.a, "a"), (tc.id, "id")):
                by_obj = meta._index_for_key(col, False)
                by_name = meta._index_for_key(name, False)
                assert by_obj == by_name, (
                    f"call {n} (hit={n>1}): col {name} index {by_obj} vs {by_name}"
                )
            row = raw.mappings().first()
            assert row is not None
            assert row[tc.id] == ident and row["id"] == ident
            assert row[tc.a] == ident * 10 and row["a"] == ident * 10
            assert row[tc.b] == ident * 100 and row["b"] == ident * 100
            sess.commit()
    with engine.connect() as conn:
        remaining = conn.execute(select(func.count()).select_from(T)).scalar()
        assert remaining == 3, f"expected 3 rows left, got {remaining}"
