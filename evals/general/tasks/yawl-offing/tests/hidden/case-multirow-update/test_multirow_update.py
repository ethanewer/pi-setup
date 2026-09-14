"""Hidden case 1: UPDATE .. RETURNING, 4 columns, declared order != returning
order, multi-row-style where, two executions (cache miss then hit). Assert the
raw cursor keymap is stable and the returned values are right per row."""
from sqlalchemy import create_engine, update, Integer
from sqlalchemy.orm import Session, DeclarativeBase, mapped_column, Mapped


class Base(DeclarativeBase):
    pass


class T(Base):
    __tablename__ = "t4"
    # declared column order: id, w, v, u
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    w: Mapped[int] = mapped_column(Integer)
    v: Mapped[int] = mapped_column(Integer)
    u: Mapped[int] = mapped_column(Integer)


def _run(ident):
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    with engine.begin() as c:
        c.execute(
            T.__table__.insert(),
            [dict(id=i, w=i * 10, v=i * 100, u=i * 1000) for i in range(1, 6)],
        )
    opts = {"synchronize_session": "fetch"}
    for n, ident in enumerate((ident, ident + 1), 1):
        stmt = (
            update(T)
            .where(T.id == ident)
            .values(v=777, w=888)
            .returning(T.u, T.id, T.w, T.v)  # order u,id,w,v vs declared id,w,v,u
        )
        with Session(engine) as sess:
            res = sess.execute(stmt, execution_options=opts)
            raw = res.raw
            meta = raw._metadata
            tc = T.__table__.c
            for col, name in ((tc.u, "u"), (tc.id, "id"), (tc.w, "w"), (tc.v, "v")):
                by_obj = meta._index_for_key(col, False)
                by_name = meta._index_for_key(name, False)
                assert by_obj == by_name, (
                    f"call {n}: col {name} index {by_obj} vs {by_name}"
                )
            row = raw.mappings().first()
            assert row is not None
            assert row[tc.id] == ident and row["id"] == ident
            assert row[tc.w] == 888 and row["w"] == 888
            assert row[tc.v] == 777 and row["v"] == 777
            assert row[tc.u] == ident * 1000 and row["u"] == ident * 1000
    return True


def test_h1_first_caller():
    assert _run(1)


def test_h1_second_caller():
    assert _run(2)
