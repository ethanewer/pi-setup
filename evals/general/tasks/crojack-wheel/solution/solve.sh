#!/usr/bin/env bash
# Oracle for crojack-wheel. Writes the reproduction deliverable, repairs the
# exact upstream cause in the real tree, and proves both directions: the
# reproduction flips from failing to passing, and the project's own session
# suite stays green.
set -u
set -e
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

# ---- 1. the deliverable reproduction script ---------------------------------
cat > /app/src/repro_issue.py <<'PY'
#!/usr/bin/env python3
"""Reproduction: Session.get() with with_for_update=False on an object that
is already in the session's identity map still emits a real SELECT, while the
same call with the flag omitted or None short-circuits to the identity map.

Exit 0 + "OK" when the flagged call emits zero additional statements.
Exit 1 + "extra selects: N" when it emits one or more.
"""
import sys

from sqlalchemy import Integer, create_engine, event
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column

engine = create_engine("sqlite://")


class Base(DeclarativeBase):
    pass


class Item(Base):
    __tablename__ = "item"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)


Base.metadata.create_all(engine)

with Session(engine) as s:
    s.add(Item(id=7))
    s.commit()

with Session(engine) as s:
    loaded = s.get(Item, 7)
    assert loaded is not None

    emitted = []
    @event.listens_for(engine, "before_cursor_execute")
    def _count(conn, cur, stmt, params, ctx, exe):
        emitted.append(stmt)

    s.get(Item, 7, with_for_update=False)

if emitted:
    print(f"extra selects: {len(emitted)}")
    sys.exit(1)
print("OK")
sys.exit(0)
PY
chmod +x /app/src/repro_issue.py

# ---- 2. repair the source-level cause --------------------------------------
python3 - <<'PY'
import pathlib

p = pathlib.Path("/app/src/lib/sqlalchemy/orm/session.py")
src = p.read_text()

old_fastpath = """        if (
            not populate_existing
            and not mapper.always_refresh
            and with_for_update is None
        ):"""
new_fastpath = """        for_update_arg = ForUpdateArg._from_argument(with_for_update)

        if (
            not populate_existing
            and not mapper.always_refresh
            and for_update_arg is None
        ):"""

old_assign = """        if with_for_update is not None:
            statement._for_update_arg = ForUpdateArg._from_argument(
                with_for_update
            )"""
new_assign = """        if for_update_arg is not None:
            statement._for_update_arg = for_update_arg"""

if src.count(old_fastpath) != 1:
    raise SystemExit(f"oracle: fast-path guard not found exactly once "
                     f"(count={src.count(old_fastpath)})")
if src.count(old_assign) != 1:
    raise SystemExit(f"oracle: for_update_arg assignment not found exactly once "
                     f"(count={src.count(old_assign)})")

src = src.replace(old_fastpath, new_fastpath).replace(old_assign, new_assign)
p.write_text(src)
print("oracle: hoisted ForUpdateArg._from_argument and gated the "
      "identity-map fast path on for_update_arg is None")
PY

# ---- 3. prove the reproduction now passes ----------------------------------
echo "--- reproduction on repaired tree ---"
python3 /app/src/repro_issue.py

# ---- 4. prove the project's own suite is still green ------------------------
echo "--- project's own suite (test/orm/test_session.py) ---"
python3 -m pytest test/orm/test_session.py -q -p no:cacheprovider 2>&1 | tail -2

echo "ORACLE DONE"