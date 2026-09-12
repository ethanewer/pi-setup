"""Compile-level hidden cases: table shapes the upstream regression test does
not use, plus regression guards that the single-option DDL is unchanged.

The upstream test asserts the exact combined DDL for a bare one-column table.
These cases verify the comma separation holds for other table shapes and that
the single-option output keeps its historical form (no comma, no reordering).
"""

import re

from sqlalchemy import CheckConstraint, Column, Integer, MetaData, Table
from sqlalchemy.dialects import sqlite as sqlite_dialect
from sqlalchemy.schema import CreateTable


def _ddl(column, *others, **options):
    m = MetaData()
    t = Table("sample", m, column, *others, **options)
    return str(CreateTable(t).compile(dialect=sqlite_dialect.dialect()))


def _norm(sql):
    return re.sub(r"\s+", " ", sql).strip()


def test_combined_options_with_named_check_constraint():
    ddl = _norm(
        _ddl(
            Column("id", Integer, primary_key=True),
            CheckConstraint("id > 0", name="positive_id"),
            sqlite_with_rowid=False,
            sqlite_strict=True,
        )
    )
    assert ddl.endswith("WITHOUT ROWID, STRICT")
    assert "WITHOUT ROWID STRICT" not in ddl


def test_combined_options_without_primary_key_still_compiles():
    # the upstream case has no PK either; keep the comma rule regardless of
    # the exact column list
    ddl = _norm(_ddl(Column("n", Integer), sqlite_with_rowid=False, sqlite_strict=True))
    assert "WITHOUT ROWID, STRICT" in ddl


def test_without_rowid_alone_has_no_trailing_comma():
    ddl = _norm(_ddl(Column("id", Integer, primary_key=True), sqlite_with_rowid=False))
    assert ddl.endswith("WITHOUT ROWID")
    assert "STRICT" not in ddl.upper()
    assert not ddl.rstrip().endswith(",")


def test_strict_alone_has_no_comma():
    ddl = _norm(_ddl(Column("id", Integer, primary_key=True), sqlite_strict=True))
    assert ddl.endswith("STRICT")
    assert "WITHOUT ROWID" not in ddl
    assert not ddl.rstrip().endswith(",")


def test_no_options_emits_no_extension_clause():
    ddl = _norm(_ddl(Column("id", Integer, primary_key=True)))
    assert ddl.endswith(")")
    assert "STRICT" not in ddl.upper()
    assert "WITHOUT ROWID" not in ddl.upper()