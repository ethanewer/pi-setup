#!/usr/bin/env python3
"""Hidden case: composite (two-column) primary key.

The upstream regression test only covers a single-integer primary key. Here
the mapped table has a two-column primary key; the object is loaded with a
composite identity and the flagged Session.get(..., with_for_update=False)
on the already-loaded object must not emit any additional statement.

Exit 0 + "OK" when correct; exit 1 + "extra selects: N" when the flagged
call still hits the database; exit 2 on identity violation.
"""
import os
import sys

libpath = os.environ.get("PYTHONPATH", "").split(os.pathsep)[0]
if libpath:
    sys.path.insert(0, libpath)

from sqlalchemy import create_engine, event  # noqa: E402
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column  # noqa: E402

engine = create_engine("sqlite://")


class Base(DeclarativeBase):
    pass


class Cell(Base):
    __tablename__ = "cell"
    row: Mapped[int] = mapped_column(primary_key=True)
    col: Mapped[int] = mapped_column(primary_key=True)
    value: Mapped[str] = mapped_column(default="v")


Base.metadata.create_all(engine)

with Session(engine) as s:
    s.add(Cell(row=2, col=5, value="c25"))
    s.add(Cell(row=9, col=1, value="c91"))
    s.commit()

with Session(engine) as s:
    first = s.get(Cell, (2, 5))
    assert first is not None, "initial composite get returned nothing"

    emitted = []
    @event.listens_for(engine, "before_cursor_execute")
    def _count(conn, cur, stmt, params, ctx, exe):
        emitted.append(stmt)

    second = s.get(Cell, (2, 5), with_for_update=False)

    if second is not first:
        print("FAIL: second get returned a different instance (identity map missed)")
        sys.exit(2)
    if emitted:
        print(f"extra selects: {len(emitted)}")
        sys.exit(1)

print("OK")
sys.exit(0)