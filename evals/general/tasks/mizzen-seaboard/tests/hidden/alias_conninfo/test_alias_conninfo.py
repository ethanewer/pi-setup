# Hidden case 1 for mizzen-seaboard: the same client_encoding resolution
# path (psycopg._encodings.conninfo_encoding) exercised from documented
# PostgreSQL alias names, casing variants and conninfo syntax shapes that the
# upstream regression test (tests/test_encodings.py::test_conninfo_encoding)
# does not use. All alias rows fail at the parent commit (silent utf-8
# fallback) and pass on a tree with the alias table fixed.
import pytest

import psycopg
from psycopg import _encodings as encodings


@pytest.mark.parametrize(
    "conninfo, pyenc",
    [
        # documented alias names the upstream regression test does not use
        ("user=foo dbname=bar client_encoding=WIN932", "shift_jis"),
        ("user=foo dbname=bar client_encoding=ShiftJIS", "shift_jis"),
        ("user=foo dbname=bar client_encoding=SHIFT_JIS", "shift_jis"),
        ("user=foo dbname=bar client_encoding=Windows932", "shift_jis"),
        ("user=foo dbname=bar client_encoding=msKANJI", "shift_jis"),
        ("user=foo dbname=bar client_encoding=WIN949", "cp949"),
        ("user=foo dbname=bar client_encoding=Windows949", "cp949"),
        ("user=foo dbname=bar client_encoding=WIN950", "big5"),
        ("user=foo dbname=bar client_encoding=Windows950", "big5"),
        ("user=foo dbname=bar client_encoding=WIN936", "gbk"),
        ("user=foo dbname=bar client_encoding=KOI8", "koi8-r"),
        ("user=foo dbname=bar client_encoding=ALT", "cp866"),
        ("user=foo dbname=bar client_encoding=ABC", "cp1258"),
        ("user=foo dbname=bar client_encoding=TCVN5712", "cp1258"),
        ("user=foo dbname=bar client_encoding=VSCII", "cp1258"),
        ("user=foo dbname=bar client_encoding=WIN", "cp1251"),
        ("user=foo dbname=bar client_encoding=ISO88591", "iso8859-1"),
        ("user=foo dbname=bar client_encoding=ISO885915", "iso8859-15"),
        # conninfo syntax variants (comma style, reordered params)
        ("user=foo, dbname=bar, client_encoding=KOI8", "koi8-r"),
        ("client_encoding=WIN932 user=alice dbname=shop", "shift_jis"),
        ("host=localhost dbname=db1 client_encoding=ALT user=root", "cp866"),
        # canonical names must keep working
        ("user=foo dbname=bar client_encoding=EUC_JP", "euc_jp"),
        ("user=foo dbname=bar client_encoding=SJIS", "shift_jis"),
        ("user=foo dbname=bar client_encoding=UHC", "cp949"),
        ("user=foo dbname=bar client_encoding=WIN1258", "cp1258"),
        # unknown / unsupported names still fall back to utf-8, silently
        ("user=foo dbname=bar client_encoding=WAT", "utf-8"),
        ("user=foo dbname=bar client_encoding=EUC_TW", "utf-8"),
    ],
)
def test_alias_conninfo(conninfo, pyenc):
    assert encodings.conninfo_encoding(conninfo) == pyenc