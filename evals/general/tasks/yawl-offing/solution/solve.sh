#!/bin/bash
# Oracle for yawl-offing: applies the real upstream fix to the real
# sqlalchemy/sqlalchemy tree at /app/src, writes the reproduction and summary
# deliverables, then proves the work in both directions with the project's own
# machinery:
#   - /app/repro.py passes against the repaired tree;
#   - /app/repro.py fails against the pristine pre-fix copy at
#     /opt/pristine-lib (PYTHONPATH override);
#   - the upstream golden regression test (extracted from the fix commit into
#     /opt/golden at image build time) passes when planted into the tree;
#   - the project's own test/orm/dml suite stays green.
# Reads only /app, /solution and /opt; never /tests.
set -u

cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

git apply --check /solution/fix.patch || {
    echo "oracle: fix.patch does not apply to a clean pinned tree" >&2
    exit 1
}
git apply /solution/fix.patch
echo "oracle: applied the ORM bulk-UPDATE/DELETE RETURNING cache-adaptation fix"

cat > /app/repro.py <<'PY'
#!/usr/bin/env python3
"""Failing reproduction for the ORM UPDATE..RETURNING cache-hit mislabel bug.

Contract: plain python3, no pytest; fresh in-memory sqlite; mapped table whose
DECLARED column order differs from the .returning() order; the same statement
shape executed twice against the same engine (first call populates the
compiled statement cache, second is a cache hit) with
execution_options={"synchronize_session": "fetch"}; on BOTH executions the raw
Core-level result metadata must map each returned column to the same physical
index by Column object and by string name, and the values read back through
result.raw.mappings() must be exactly what the UPDATE produced. Exits 0 iff
everything holds.
"""
import sys

from sqlalchemy import create_engine, update, Integer
from sqlalchemy.orm import Session, DeclarativeBase, mapped_column, Mapped


class Base(DeclarativeBase):
    pass


class T(Base):
    __tablename__ = "t"
    # declared column order: id, b, a   (deliberately != returning order)
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    b: Mapped[int] = mapped_column(Integer)
    a: Mapped[int] = mapped_column(Integer)


def main():
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    with engine.begin() as c:
        c.execute(
            T.__table__.insert(),
            [dict(id=i, a=i * 10, b=i * 100) for i in range(1, 5)],
        )

    opts = {"synchronize_session": "fetch"}
    ok = True
    tc = T.__table__.c
    for n, ident in enumerate((1, 2), 1):
        stmt = (
            update(T)
            .where(T.id == ident)
            .values(b=999)
            .returning(T.id, T.a, T.b)  # returning order id, a, b
        )
        with Session(engine) as sess:
            result = sess.execute(stmt, execution_options=opts)
            raw = result.raw
            meta = raw._metadata
            # keymap: Column-object index must equal string-name index
            for col, name in ((tc.id, "id"), (tc.a, "a"), (tc.b, "b")):
                by_obj = meta._index_for_key(col, False)
                by_name = meta._index_for_key(name, False)
                if by_obj != by_name:
                    print(
                        "call %d: column %r resolves to index %d by Column "
                        "object but %d by string name"
                        % (n, name, by_obj, by_name)
                    )
                    ok = False
            # values through the raw (Core-level) result
            row = raw.mappings().first()
            expected = {tc.id: ident, tc.a: ident * 10, tc.b: 999}
            for col in (tc.id, tc.a, tc.b):
                got_obj = row[col]
                got_name = row[col.key]
                if got_obj != expected[col] or got_name != expected[col]:
                    print(
                        "call %d: value of %s is %s (Column-object) / %s "
                        "(string); expected %d"
                        % (n, col.key, got_obj, got_name, expected[col])
                    )
                    ok = False
    print("RAW KEYMAP STABLE, VALUES CORRECT" if ok
          else "KEYMAP CORRUPTED (cache-hit execution mislabels columns)")
    sys.exit(0 if ok else 1)


main()
PY
chmod +x /app/repro.py
echo "oracle: wrote /app/repro.py"

cat > /app/summary.md <<'MD'
# Change summary (oracle)

Bug: an ORM UPDATE (or DELETE) statement that uses `.returning()` whose column
order differs from the order the columns are declared on the mapped table,
executed through a Session with `execution_options={"synchronize_session":
"fetch"}`, returns mislabeled columns on the second execution of the same
statement shape: a compiled-cache hit. The corruption lives in the
cursor-level result metadata of the underlying Core result (`result.raw`): the
positon each returned column resolves to by Column object diverges from the
position it resolves to by string name, so the values of two columns are
exchanged. It is masked by ORM-level row access (which re-processes positions)
and by cached row getters, and the DELETE variant happened to pass at the
parent while UPDATE failed, which made the symptom look random.

Cause: in ORM bulk UPDATE/DELETE compile state
(`_BulkUDCompileState._or_create_orm_setting` in
`lib/sqlalchemy/orm/bulk_persistence.py`), the returned `execution_options` for
`synchronize_session="fetch"` did not carry the ORM load execution options
(`context._orm_load_exec_options`) that disable result-level `adapt_to_context`
for precisely this "two level" statement situation (the invoked ORM statement
holds the user's returning columns while the cached Core statement returns
mapper-order columns, so the two are not positionally aligned). The ORM
INSERT path already merged those options; the bulk UPDATE/DELETE path did not.

Change: merged `context._orm_load_exec_options` into the effective
`execution_options` returned by `_or_create_orm_setting`, exactly as the
project's own INSERT path already does, so the core result is not positionally
re-adapted against the user's returning order on cache hits.

Verification:
- `/app/repro.py` fails on the pristine pre-fix tree (call 2: `row[T.a]` is
  the value of `b`, keymap diverges) and passes on the repaired tree.
- The upstream regression test for this bug (class
  `CacheAdaptReturningOrderTest`, extracted from the fix commit into
  `/opt/golden`) passes both its `[update]` and `[delete]` variants when
  planted into the tree.
- `python3 -m pytest test/orm/dml -q -p no:cacheprovider` stays green
  (956+ passed, skips unchanged).
MD
echo "oracle: wrote /app/summary.md"

# ---- prove the work ---------------------------------------------------------
if ! python3 /app/repro.py > /tmp/oracle_repro_fixed.out 2>&1; then
    echo "oracle: /app/repro.py FAILED on the repaired tree; output:" >&2
    cat /tmp/oracle_repro_fixed.out >&2
    exit 1
fi
echo "oracle: repro passes on the repaired tree"

if PYTHONPATH=/opt/pristine-lib python3 /app/repro.py \
        > /tmp/oracle_repro_pristine.out 2>&1; then
    echo "oracle: /app/repro.py PASSED against the pristine pre-fix tree" >&2
    echo "oracle: (expected failure on the buggy tree - symptom not reproduced?)" >&2
    cat /tmp/oracle_repro_pristine.out >&2
    exit 1
fi
echo "oracle: repro fails on the pristine pre-fix tree (symptom real)"

# golden: plant temporarily, run the regression class, restore the tree file
cp /opt/golden/test_orm_upd_del_assorted.py \
   test/orm/dml/test_orm_upd_del_assorted.py || {
    echo "oracle: cannot plant golden test" >&2
    exit 1
}
if ! python3 -m pytest \
      "test/orm/dml/test_orm_upd_del_assorted.py::CacheAdaptReturningOrderTest" \
      -q -p no:cacheprovider > /tmp/oracle_golden.log 2>&1; then
    tail -25 /tmp/oracle_golden.log >&2
    echo "oracle: upstream regression test failed on the fixed tree" >&2
    exit 1
fi
grep -q "2 passed" /tmp/oracle_golden.log || {
    echo "oracle: regression class did not pass 2/2" >&2
    exit 1
}
echo "oracle: upstream regression test passes (2/2)"
git checkout -q -- test/orm/dml/test_orm_upd_del_assorted.py
rm -rf .pytest_cache __pycache__
dirty=$(git status --porcelain)
if [ -n "$dirty" ] && [ "$dirty" != " M lib/sqlalchemy/orm/bulk_persistence.py" ]; then
    echo "oracle: unexpected tree dirt after golden run: $dirty" >&2
    exit 1
fi

# project's own dml suite stays green
if ! python3 -m pytest test/orm/dml -q -p no:cacheprovider \
        > /tmp/oracle_dml.log 2>&1; then
    tail -25 /tmp/oracle_dml.log >&2
    echo "oracle: test/orm/dml failed on the fixed tree" >&2
    exit 1
fi
tail -1 /tmp/oracle_dml.log
echo "oracle: fix applied, deliverables written, repro proven both directions, golden green, dml green"
exit 0