#!/bin/bash
#
# ds-sash-builder oracle. Does the REAL work from a pristine container:
# writes the window-function extension deliverable /app/qb/window.py
# (OverSpec + window_item per the documented contract, reusing the shipped
# core's quote/render_order helpers), runs the shipped /app/demo.py to
# regenerate /app/demo_out.sql, and self-checks the five demo queries plus
# contract validation. Never reads /tests.
set -euo pipefail

cat > /app/qb/window.py <<'PYEOF'
"""Window-function support for the sash query builder.

Extension contract (task brief):

* ``OverSpec(function, args=(), partition_by=(), order_by=(), frame=None)``
  — validated at construction (ValueError on unknown function, wrong arg
  count for the function, non-pair frame, or frame-bound text outside the
  documented vocabulary);
* ``window_item(alias, over) -> str`` — the complete canonical SELECT item,
  e.g. ``ROW_NUMBER() OVER (PARTITION BY "dept" ORDER BY "salary" DESC)
  AS "rn"``.

Identifiers and ORDER BY entries reuse the shipped core helpers, so the
quoting and rendering rules are identical everywhere.
"""
from .core import quote, render_order

_FUNCTIONS = ('row_number', 'rank', 'dense_rank', 'sum', 'avg', 'count')
_AGGREGATES = ('sum', 'avg', 'count')


def _render_bound(bound):
    """Render one frame bound; raise ValueError outside the vocabulary."""
    b = str(bound).strip().lower()
    if b == 'current row':
        return 'CURRENT ROW'
    if b == 'unbounded preceding':
        return 'UNBOUNDED PRECEDING'
    if b == 'unbounded following':
        return 'UNBOUNDED FOLLOWING'
    parts = b.split()
    if len(parts) == 2 and parts[0].isdigit() and parts[1] in (
            'preceding', 'following'):
        return parts[0] + ' ' + parts[1].upper()
    raise ValueError('invalid frame bound: %r' % (bound,))


class OverSpec:
    """Window specification (function, args, partition, order, frame)."""

    def __init__(self, function, args=(), partition_by=(), order_by=(),
                 frame=None):
        self.function = str(function)
        self.args = tuple(args)
        self.partition_by = tuple(partition_by)
        self.order_by = tuple(order_by)
        self.frame = tuple(frame) if frame is not None else None
        if self.function not in _FUNCTIONS:
            raise ValueError('unknown window function: %r' % function)
        if self.function in _AGGREGATES:
            if len(self.args) != 1:
                raise ValueError('%s needs exactly one argument'
                                 % self.function)
        elif self.args:
            raise ValueError('%s takes no arguments' % self.function)
        if self.frame is None:
            return
        if len(self.frame) != 2:
            raise ValueError('frame must be a (start, end) pair or None')
        _render_bound(self.frame[0])
        _render_bound(self.frame[1])


def window_item(alias, over):
    """Render the canonical SELECT item for one window expression."""
    fn = over.function.upper()
    if fn in ('SUM', 'AVG', 'COUNT'):
        call = '%s(%s)' % (fn, quote(over.args[0]))
    else:
        call = '%s()' % fn
    inner = []
    if over.partition_by:
        inner.append('PARTITION BY ' + ', '.join(
            quote(c) for c in over.partition_by))
    if over.order_by:
        inner.append('ORDER BY ' + ', '.join(
            render_order(o) for o in over.order_by))
    if over.frame is not None:
        inner.append('ROWS BETWEEN %s AND %s' % (
            _render_bound(over.frame[0]), _render_bound(over.frame[1])))
    over_txt = 'OVER (' + (' '.join(inner) if inner else '') + ')'
    return '%s %s AS %s' % (call, over_txt, quote(alias))
PYEOF

# ---- Regenerate the visible demo output deliverable.
python3 /app/demo.py
test -s /app/demo_out.sql

# ---- Self-check: the five demo queries must render the documented
# canonical strings, and contract validation must raise ValueError.
python3 - <<'PY'
import sys
sys.path.insert(0, "/app")

from qb import Qb
from qb.window import OverSpec, window_item

expected = [
    'SELECT "name", "dept", "salary", '
    'ROW_NUMBER() OVER (PARTITION BY "dept" ORDER BY "salary" DESC) AS "rn" '
    'FROM "payroll" WHERE active = 1',
    'SELECT "month", "region", "sales", '
    'SUM("sales") OVER (PARTITION BY "region" ORDER BY "month" '
    'ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS "run_total" '
    'FROM "monthly_sales" ORDER BY "region", "month"',
    'SELECT "student_id", "subject", "score", '
    'RANK() OVER (PARTITION BY "subject" ORDER BY "score" DESC) AS "subj_rank", '
    'DENSE_RANK() OVER (ORDER BY "score" DESC) AS "global_rank" '
    'FROM "grades" WHERE score is not null ORDER BY "subject", "score" DESC',
    'SELECT "item", "qty", '
    'AVG("qty") OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS "share", '
    'COUNT("item") OVER (ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS "overall" '
    'FROM "inventory"',
    'SELECT "trip_id", "miles", '
    'SUM("miles") OVER (ROWS BETWEEN CURRENT ROW AND 2 FOLLOWING) AS "total" '
    'FROM "fleet_trips" WHERE miles > 0 ORDER BY "trip_id" DESC',
]

with open("/app/demo_out.sql", encoding="utf-8") as fh:
    got = fh.read()
assert got == "\n".join(expected) + "\n", "demo output mismatch"

# API surface spot checks.
assert window_item("rn", OverSpec(function="row_number",
                                  partition_by=("dept",),
                                  order_by=("salary desc",))) == (
    'ROW_NUMBER() OVER (PARTITION BY "dept" ORDER BY "salary" DESC) AS "rn"')

def raises(fn):
    try:
        fn()
    except ValueError:
        return True
    return False

assert raises(lambda: OverSpec(function="lag"))
assert raises(lambda: OverSpec(function="sum", args=()))
assert raises(lambda: OverSpec(function="sum", args=("a", "b")))
assert raises(lambda: OverSpec(function="rank", args=("x",)))
assert raises(lambda: OverSpec(function="avg", args=("x",),
                               frame=("5 sideways", "current row")))
assert raises(lambda: OverSpec(function="avg", args=("x",), frame=("a",)))

# Deterministic canonical + exclusion of hidden cross-checks.
q = (Qb().select("sku").select_window(
        "zr", OverSpec(function="sum", args=("qty",),
                       partition_by=("zone",),
                       order_by=("sku asc",),
                       frame=("2 preceding", "current row")))
     .from_("stock").where("qty > 0").order_by("zone").sql())
assert q == ('SELECT "sku", SUM("qty") OVER (PARTITION BY "zone" '
             'ORDER BY "sku" ASC ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) '
             'AS "zr" FROM "stock" WHERE qty > 0 ORDER BY "zone"'), q

print("ds-sash-builder oracle self-check passed")
PY

echo "ds-sash-builder oracle complete -> /app/qb/window.py and /app/demo_out.sql"