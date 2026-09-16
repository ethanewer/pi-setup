# Hidden case 2 for mizzen-seaboard: the same code path one level down -
# psycopg._encodings.pg2pyenc applied directly to documented PostgreSQL
# alias names (plus the py2pgenc reverse direction and the unknown-name
# failure contract). The alias rows raise NotSupportedError at the parent
# commit (aliases absent from the mapping) and resolve on a fixed tree.
import pytest

import psycopg
from psycopg import _encodings as encodings


@pytest.mark.parametrize(
    "name, pyenc",
    [
        (b"MSKANJI", "shift_jis"),
        (b"mskanji", "shift_jis"),
        (b"ShiftJIS", "shift_jis"),
        (b"SHIFT_JIS", "shift_jis"),
        (b"SHIFT-JIS", "shift_jis"),
        (b"WIN932", "shift_jis"),
        (b"WIN949", "cp949"),
        (b"ISO88591", "iso8859-1"),
        (b"KOI8", "koi8-r"),
        (b"ALT", "cp866"),
        (b"Unicode", "utf-8"),
    ],
)
def test_pg2py_alias(name, pyenc):
    assert encodings.pg2pyenc(name) == pyenc


@pytest.mark.parametrize(
    "pyenc, pgenc",
    [
        ("shift_jis", b"SJIS"),
        ("cp949", b"UHC"),
        ("utf-8", b"UTF8"),
        ("big5", b"BIG5"),
        ("koi8-r", b"KOI8R"),
    ],
)
def test_py2pg_stable(pyenc, pgenc):
    assert encodings.py2pgenc(pyenc) == pgenc


@pytest.mark.parametrize("name", [b"WAT", b"MAKE-UP", b"EUC_TW", b"MULE_INTERNAL"])
def test_pg2py_unknown_raises(name):
    with pytest.raises(psycopg.NotSupportedError):
        encodings.pg2pyenc(name)