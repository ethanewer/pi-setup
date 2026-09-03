#!/usr/bin/env python3
"""Sash query builder — visible demonstration of window-function support.

Running this script regenerates the demo output deliverable
``/app/demo_out.sql``::

    python3 /app/demo.py

The script builds every query strictly through the public builder API
(`Qb.select/select_window/from_/where/order_by` plus `OverSpec`), so it
cannot produce output until the window extension at `/app/qb/window.py` is
fully implemented.

`DEMO_SPECS` is the machine-readable description of the demo, one dict per
query.  The verifier re-renders these same specs with an independent
implementation and requires the demo's stdout and `/app/demo_out.sql` to
match byte-for-byte.

Spec fields:

* ``select``   — column identifiers rendered through ``Qb.select``
* ``windows``  — ``(alias, OverSpec kwargs)`` pairs rendered through
  ``Qb.select_window``
* ``from_``    — table identifier
* ``where``    — raw predicate fragments (verbatim, AND-joined)
* ``order_by`` — outer ORDER BY entries (``col`` or ``col asc/desc``)
"""
import sys

sys.path.insert(0, "/app")

from qb import Qb
from qb.window import OverSpec  # the deliverable extension module

DEMO_SPECS = [
    {
        "select": ("name", "dept", "salary"),
        "windows": [
            ("rn", {"function": "row_number", "partition_by": ("dept",),
                    "order_by": ("salary desc",)}),
        ],
        "from_": "payroll",
        "where": ("active = 1",),
        "order_by": (),
    },
    {
        "select": ("month", "region", "sales"),
        "windows": [
            ("run_total", {"function": "sum", "args": ("sales",),
                           "partition_by": ("region",),
                           "order_by": ("month",),
                           "frame": ("unbounded preceding", "current row")}),
        ],
        "from_": "monthly_sales",
        "where": (),
        "order_by": ("region", "month"),
    },
    {
        "select": ("student_id", "subject", "score"),
        "windows": [
            ("subj_rank", {"function": "rank", "partition_by": ("subject",),
                           "order_by": ("score desc",)}),
            ("global_rank", {"function": "dense_rank",
                             "order_by": ("score desc",)}),
        ],
        "from_": "grades",
        "where": ("score is not null",),
        "order_by": ("subject", "score desc"),
    },
    {
        "select": ("item", "qty"),
        "windows": [
            ("share", {"function": "avg", "args": ("qty",),
                       "frame": ("unbounded preceding", "unbounded following")}),
            ("overall", {"function": "count", "args": ("item",),
                         "frame": ("1 preceding", "1 following")}),
        ],
        "from_": "inventory",
        "where": (),
        "order_by": (),
    },
    {
        "select": ("trip_id", "miles"),
        "windows": [
            ("total", {"function": "sum", "args": ("miles",),
                       "partition_by": (),
                       "order_by": (),
                       "frame": ("current row", "2 following")}),
        ],
        "from_": "fleet_trips",
        "where": ("miles > 0",),
        "order_by": ("trip_id desc",),
    },
]


def build_query(spec):
    """Build a Qb from a spec dict using only the public API."""
    qb = Qb()
    if spec.get("select"):
        qb.select(*spec["select"])
    for alias, over_kw in spec.get("windows", []):
        qb.select_window(alias, OverSpec(**over_kw))
    qb.from_(spec["from_"])
    if spec.get("where"):
        qb.where(*spec["where"])
    if spec.get("order_by"):
        qb.order_by(*spec["order_by"])
    return qb


def main():
    lines = [build_query(s).sql() for s in DEMO_SPECS]
    text = "\n".join(lines) + "\n"
    sys.stdout.write(text)
    with open("/app/demo_out.sql", "w", encoding="utf-8") as fh:
        fh.write(text)


if __name__ == "__main__":
    main()