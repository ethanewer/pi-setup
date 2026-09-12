#!/usr/bin/env python3
"""Apply the duplicate-column fix to psycopg's row factory (the real solver).

Reads the checked-out ``psycopg/psycopg/rows.py`` at /app/src and wraps the
``collections.namedtuple()`` call in a ``try/except ValueError`` that re-raises
as ``psycopg.errors.DataError``, the same change the upstream fix makes. The
``psycopg.errors`` module is already imported as ``e`` in that file, so the
change needs no new imports.

Fails loudly if the expected buggy fragment is not found exactly once, so the
oracle cannot silently no-op on an unexpected tree.
"""

import sys
from pathlib import Path

OLD = """    snames = tuple(_as_python_identifier(n.decode(enc)) for n in names)
    return namedtuple("Row", snames)  # type: ignore[return-value]
"""

NEW = """    snames = tuple(_as_python_identifier(n.decode(enc)) for n in names)
    try:
        return namedtuple("Row", snames)  # type: ignore[return-value]
    except ValueError as ex:
        raise e.DataError(f"can't create a namedtuple row: {ex}") from None
"""


def main(path: str) -> int:
    p = Path(path)
    if not p.is_file():
        print(f"FATAL: {path} does not exist", file=sys.stderr)
        return 1
    text = p.read_text(encoding="utf-8")
    if NEW in text:
        print(f"{path}: fix already present, nothing to do")
        return 0
    if text.count(OLD) != 1:
        print(
            f"FATAL: expected buggy fragment found {text.count(OLD)} times "
            f"(need exactly 1); refusing to patch",
            file=sys.stderr,
        )
        return 1
    p.write_text(text.replace(OLD, NEW), encoding="utf-8")
    print(f"{path}: patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "/app/src/psycopg/psycopg/rows.py"))