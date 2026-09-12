"""Hidden case for bracket-fathom: end-to-end through the row factory.

The upstream regression test calls the row-type builder directly. These cases
drive the same code path through the pieces the connection machinery uses:
the namedtuple row factory invoked on a cursor that has just received a
TUPLES_OK result (mimicking what a real join produces), plus guards that the
non-duplicate path and the no-result path are unchanged.
"""

import pytest

import psycopg
from psycopg import rows
from psycopg.pq import ExecStatus


class FakePgResult:
    """Mimics the bits of libpq's PGresult the row factories read."""

    def __init__(self, names):
        self._names = list(names)
        self.nfields = len(self._names)
        self.status = ExecStatus.TUPLES_OK

    def fname(self, i):
        return self._names[i]


class FakeCursor:
    """Mimics a cursor that has a TUPLES_OK result stored."""

    def __init__(self, names):
        self.pgresult = FakePgResult(names)
        self._encoding = "utf-8"


class EmptyCursor:
    """Mimics a cursor that has not received a result."""

    pgresult = None
    _encoding = "utf-8"


def test_join_like_duplicate_columns_flow_through_factory():
    # SELECT film.id, book.id FROM film JOIN book ... creates exactly this
    cur = FakeCursor([b"id", b"id"])
    with pytest.raises(psycopg.DataError):
        rows.namedtuple_row(cur)


def test_mangled_duplicates_flow_through_factory():
    # columns named e.g. "a-b" in one relation and "a_b" in the other
    cur = FakeCursor([b"a-b", b"a_b"])
    with pytest.raises(psycopg.DataError):
        rows.namedtuple_row(cur)


def test_distinct_names_flow_through_factory_unchanged():
    cur = FakeCursor([b"id", b"name"])
    maker = rows.namedtuple_row(cur)
    row = maker([1, "bob"])
    assert (row.id, row.name) == (1, "bob")
    assert type(row).__name__ == "Row"


def test_factory_without_result_raises_interface_error():
    # a factory called with no result returns a row maker that refuses rows
    with pytest.raises(psycopg.InterfaceError):
        rows.namedtuple_row(EmptyCursor())([1, 2])