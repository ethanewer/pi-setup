#!/usr/bin/env python3
"""Reproduce the duplicate-column-name failure in the namedtuple row factory.

Run from OUTSIDE the repository root, e.g.:

    cd /tmp && python3 /app/probe_row_factory.py

Run it from /tmp because the repository root contains a top-level ``psycopg/``
subproject directory which can confuse ``import psycopg`` when Python is
started there.

psycopg is installed into site-packages as a regular (non-editable) copy taken
from the checkout at /app/src at image build time. If you change the source
tree you must reinstall it before Python sees your change:

    python3 -m pip install --force-reinstall --no-deps --no-build-isolation \
        --no-index /app/src/psycopg

This script shows what the row factory does when a query result contains two
columns with the same name.
"""

import psycopg
from psycopg import pq
from psycopg import rows


class _FakePgResult:
    """A minimal stand-in for the libpq result object behind a cursor."""

    def __init__(self, names):
        self.names = list(names)
        self.nfields = len(self.names)
        self.status = pq.ExecStatus.TUPLES_OK

    def fname(self, i):
        return self.names[i]


class _FakeCursor:
    """A minimal stand-in for a cursor that has received a query result."""

    def __init__(self, names):
        self.pgresult = _FakePgResult(names)
        self._encoding = "utf-8"


def show(label, names):
    cur = _FakeCursor(names)
    try:
        row_factory = rows.namedtuple_row(cur)
        print(f"{label}: no exception, factory returned {row_factory!r}")
    except Exception as ex:
        is_psy = isinstance(ex, psycopg.Error)
        print(
            f"{label}: raised {type(ex).__module__}.{type(ex).__name__}: {ex}"
            f"   [psycopg error: {is_psy}]"
        )


def main():
    print("psycopg loaded from:", psycopg.__file__)
    # A join can return two columns with the same name, e.g.
    #   SELECT film.id, book.id FROM film JOIN book ON ...
    show("duplicate column names (join)", [b"id", b"id"])


if __name__ == "__main__":
    main()