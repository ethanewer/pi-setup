#!/usr/bin/env python3
"""Oracle fix for the reef-sail task: repair SQLite CHECK-constraint
reflection in the checked-out SQLAlchemy tree.

The clause-boundary pattern in SQLiteDialect.get_check_constraints only
recognises 'CONSTRAINT' and 'CHECK' after the comma/whitespace, so a CHECK
constraint that is followed by a UNIQUE, PRIMARY KEY or FOREIGN KEY clause
in the stored CREATE TABLE text swallows that clause into its reflected
sqltext.  The fix extends the lookahead to all five clause keywords.

This mirrors the upstream repair (one-line change to the same pattern).
"""

import sys

OLD = r",[\s\n]*(?=CONSTRAINT|CHECK)"
NEW = r",[\s\n]*(?=CONSTRAINT|CHECK|UNIQUE|FOREIGN|PRIMARY)"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_check_constraints.py PATH", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path, encoding="utf-8") as f:
        src = f.read()
    count = src.count(OLD)
    if count != 1:
        print(
            "expected exactly one occurrence of the buggy pattern, found %d in %s"
            % (count, path),
            file=sys.stderr,
        )
        return 1
    with open(path, "w", encoding="utf-8") as f:
        f.write(src.replace(OLD, NEW))
    print("patched %s (%d replacement)" % (path, count))
    return 0


if __name__ == "__main__":
    sys.exit(main())