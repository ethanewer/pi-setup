"""Hidden case for bracket-fathom: duplicate-name detection variants.

The upstream regression test feeds two identical byte names (b"id", b"id").
These cases drive the same code path with inputs the upstream test does not
use: duplicates that only collide after the identifier mangling the row
factory applies, duplicates buried in a longer column list, a different text
encoding, and the requirement that the raised error is a psycopg error with
the fixed message wording.
"""

import pytest

import psycopg
from psycopg import rows


@pytest.mark.parametrize(
    "enc,names",
    [
        # identical bytes, first position (like a self-join on the same alias)
        ("utf-8", (b"id", b"id")),
        # duplicate buried in the middle of a larger select list
        ("utf-8", (b"id", b"name", b"id")),
        ("utf-8", (b"a", b"b", b"c", b"b", b"d")),
        # byte-distinct names that mangle to the same Python identifier:
        # "a-b" -> "a_b" (invalid chars become '_'), "a_b" is left alone
        ("utf-8", (b"a-b", b"a_b")),
        ("utf-8", (b"f.id", b"f_id")),
        # latin-1 encoded names that decode to the same identifier (p\xe9re)
        ("latin-1", (b"p\xe9re", b"p\xe9re")),
    ],
)
def test_duplicate_columns_raise_dataerror(enc, names):
    with pytest.raises(psycopg.DataError):
        rows._make_nt(enc, *names)


def test_error_message_wording():
    with pytest.raises(psycopg.DataError, match=r"can't create a namedtuple row"):
        rows._make_nt("utf-8", b"id", b"id")
    with pytest.raises(psycopg.DataError, match=r"duplicate field name"):
        rows._make_nt("utf-8", b"id", b"id")


def test_error_is_a_psycopg_error_subclass():
    try:
        rows._make_nt("utf-8", b"id", b"id")
    except Exception as ex:  # noqa: BLE001 - the module must only raise psycopg errors
        assert isinstance(ex, psycopg.errors.Error)
        assert isinstance(ex, psycopg.Error)
        assert not isinstance(ex, ValueError)
    else:  # pragma: no cover
        pytest.fail("_make_nt accepted duplicate names without raising")


def test_non_duplicate_names_still_work():
    # nothing about the fix may change the valid path
    nt = rows._make_nt("utf-8", b"id", b"name")
    r = nt(1, "bob")
    assert (r.id, r.name) == (1, "bob")
    # byte-distinct names that merely share a text prefix stay fine
    nt2 = rows._make_nt("utf-8", b"x", b"x_")
    assert nt2(1, 2) == (1, 2)