#!/usr/bin/env python3
"""Hidden case: string primary key.

Exercises the same Session.get() identity-map fast path as the upstream
regression test but with a string primary key (the upstream test only uses
an integer PK table). Loads the row via Session.get, then re-fetches it
with with_for_update=False and requires that NO additional statement is
emitted and that the identity-mapped instance is returned.

Exit 0 + "OK" when correct; exit 1 + "extra selects: N" when the flagged
call still hits the database; exit 2 on identity violation.
"""
import os
import sys

libpath = os.environ.get("PYTHONPATH", "").split(os.pathsep)[0]
if libpath:
    sys.path.insert(0, libpath)

from sqlalchemy import String, create_engine, event  # noqa: E402
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column  # noqa: E402

engine = create_engine("sqlite://")


class Base(DeclarativeBase):
    pass


class Doc(Base):
    __tablename__ = "doc"
    key: Mapped[str] = mapped_column(String(40), primary_key=True)
    body: Mapped[str] = mapped_column(String(255), default="body")


Base.metadata.create_all(engine)

with Session(engine) as s:
    s.add(Doc(key="doc-0417-a", body="payload-1"))
    s.commit()

with Session(engine) as s:
    first = s.get(Doc, "doc-0417-a")
    assert first is not None, "initial get returned nothing"

    emitted = []
    @event.listens_for(engine, "before_cursor_execute")
    def _count(conn, cur, stmt, params, ctx, exe):
        emitted.append(stmt)

    second = s.get(Doc, "doc-0417-a", with_for_update=False)

    if second is not first:
        print("FAIL: second get returned a different instance (identity map missed)")
        sys.exit(2)
    if emitted:
        print(f"extra selects: {len(emitted)}")
        sys.exit(1)

print("OK")
sys.exit(0)