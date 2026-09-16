#!/usr/bin/env python3
"""Hidden case: object entered the identity map through a SELECT statement.

The upstream regression test loads the object via Session.get() before the
flagged second call. Here the object reaches the session's identity map by
a different route -- a session.execute(select(...)) -- and the subsequent
Session.get(pk, with_for_update=False) must still short-circuit to the
identity map without emitting any additional statement.

Exit 0 + "OK" when correct; exit 1 + "extra selects: N" when the flagged
call still hits the database; exit 2 on identity violation.
"""
import os
import sys

libpath = os.environ.get("PYTHONPATH", "").split(os.pathsep)[0]
if libpath:
    sys.path.insert(0, libpath)

from sqlalchemy import create_engine, event, select  # noqa: E402
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column  # noqa: E402

engine = create_engine("sqlite://")


class Base(DeclarativeBase):
    pass


class Line(Base):
    __tablename__ = "line"
    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(default="L")


Base.metadata.create_all(engine)

with Session(engine) as s:
    s.add(Line(id=303, code="alpha"))
    s.add(Line(id=404, code="beta"))
    s.commit()

with Session(engine) as s:
    # populate the identity map via statement execution, not Session.get
    rows = s.execute(select(Line).where(Line.code == "alpha")).scalars().all()
    assert len(rows) == 1, "unexpected row count from select"
    first = rows[0]

    emitted = []
    @event.listens_for(engine, "before_cursor_execute")
    def _count(conn, cur, stmt, params, ctx, exe):
        emitted.append(stmt)

    second = s.get(Line, 303, with_for_update=False)

    if second is not first:
        print("FAIL: second get returned a different instance (identity map missed)")
        sys.exit(2)
    if emitted:
        print(f"extra selects: {len(emitted)}")
        sys.exit(1)

print("OK")
sys.exit(0)