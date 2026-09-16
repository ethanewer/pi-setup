"""Hidden case 3: UPDATE .. RETURNING returning only a SUBSET of columns in a
scrambled order (not the full declared set), where-clause id.in_(...) spanning
two rows, executed twice so the second execution is a cache hit. Both rows must
come back with the right values under Column-object AND string lookup."""
from sqlalchemy import create_engine, update, Integer
from sqlalchemy.orm import Session, DeclarativeBase, mapped_column, Mapped


class Base(DeclarativeBase):
    pass


class T(Base):
    __tablename__ = "tsub"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    x: Mapped[int] = mapped_column(Integer)
    y: Mapped[int] = mapped_column(Integer)
    z: Mapped[int] = mapped_column(Integer)


def test_h3_subset_two_rows():
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    with engine.begin() as c:
        c.execute(
            T.__table__.insert(),
            [dict(id=i, x=i * 10, y=i * 100, z=i * 1000) for i in range(1, 6)],
        )
    opts = {"synchronize_session": "fetch"}
    for n, ids in enumerate(((1, 2), (3, 4)), 1):
        stmt = (
            update(T)
            .where(T.id.in_(ids))
            .values(z=555)
            .returning(T.z, T.x)  # subset, order z,x vs declared id,x,y,z
        )
        with Session(engine) as sess:
            res = sess.execute(stmt, execution_options=opts)
            raw = res.raw
            meta = raw._metadata
            tc = T.__table__.c
            for col, name in ((tc.z, "z"), (tc.x, "x")):
                by_obj = meta._index_for_key(col, False)
                by_name = meta._index_for_key(name, False)
                assert by_obj == by_name, (
                    f"call {n}: col {name} index {by_obj} vs {by_name}"
                )
            rows = raw.mappings().all()
            assert len(rows) == 2, f"expected 2 rows, got {len(rows)}"
            got = {}
            for row in rows:
                got[row[tc.id]] = (row[tc.x], row[tc.z])
            for ident in ids:
                assert ident in got
                x, z = got[ident]
                assert x == ident * 10 and z == 555, (
                    f"row {ident}: x={x} z={z} (want {ident*10}, 555)"
                )
