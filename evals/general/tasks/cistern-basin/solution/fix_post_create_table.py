#!/usr/bin/env python3
"""Apply the SQLite table-options DDL fix to SQLAlchemy's sqlite dialect.

At the parent commit, SQLiteDDLCompiler.post_create_table concatenates the
"WITHOUT ROWID" and "STRICT" table-option clauses with a bare newline, so a
table defined with both sqlite_with_rowid=False and sqlite_strict=True
compiles to "CREATE TABLE ... WITHOUT ROWID\\n STRICT" -- DDL that SQLite
rejects with a syntax error near "STRICT".  This rewrites the method to
collect the extension clauses into a list and join them comma-separated
("WITHOUT ROWID, STRICT"), leaving the single-option and no-option output
byte-identical to before.

Idempotent; exits non-zero if the expected buggy snippet is not present.
"""

import sys
from pathlib import Path

BUGGY = """    def post_create_table(self, table):
        text = \"\"
        if table.dialect_options[\"sqlite\"][\"with_rowid\"] is False:
            text += \"\\n WITHOUT ROWID\"
        if table.dialect_options[\"sqlite\"][\"strict\"] is True:
            text += \"\\n STRICT\"
        return text
"""

FIXED = """    def post_create_table(self, table):
        table_options = []

        if not table.dialect_options[\"sqlite\"][\"with_rowid\"]:
            table_options.append(\"WITHOUT ROWID\")

        if table.dialect_options[\"sqlite\"][\"strict\"]:
            table_options.append(\"STRICT\")

        if table_options:
            return \"\\n \" + \",\\n \".join(table_options)
        else:
            return \"\"
"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_post_create_table.py PATH", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")

    if FIXED in src:
        print("base.py already carries the comma-separated fix")
        return 0
    if BUGGY not in src:
        print("FATAL: expected buggy post_create_table snippet not found",
              file=sys.stderr)
        return 1
    path.write_text(src.replace(BUGGY, FIXED, 1), encoding="utf-8")
    print(f"patched {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())