#!/usr/bin/env python3
"""Oracle fix for oarlock-haven.

Applies the upstream fix to pytest's monkeypatch undo bookkeeping in-place:

  * MonkeyPatch.delattr:  push the undo entry ONLY after delattr() succeeded
                          (previously the entry was pushed before the delete,
                          so a failing delattr left a stale entry and the
                          matching undo() re-raised the original AttributeError).
  * MonkeyPatch.setitem:  capture the old value, then push the undo entry only
                          after dic[name] = value succeeded.
  * MonkeyPatch.delitem:  capture the old value, then push the undo entry only
                          after del dic[name] succeeded.

Usage: fix_monkeypatch.py <path-to-src/_pytest/monkeypatch.py>

Every replacement is exact and must occur exactly once; the script fails
loudly otherwise, so it can never silently "fix" a tree it does not
understand.
"""

from __future__ import annotations

import sys


# --- exact snippets as they appear at the pinned parent commit ---------------

DELATTR_OLD = """            self._setattr.append((target, name, oldval))
            delattr(target, name)
"""
DELATTR_NEW = """            delattr(target, name)
            self._setattr.append((target, name, oldval))
"""

SETITEM_OLD = """        self._setitem.append((dic, name, dic.get(name, NOTSET)))
        # Not all Mapping types support indexing, but MutableMapping doesn't support TypedDict
        dic[name] = value  # type: ignore[index]
"""
SETITEM_NEW = """        oldval = dic.get(name, NOTSET)
        # Not all Mapping types support indexing, but MutableMapping doesn't support TypedDict
        dic[name] = value  # type: ignore[index]
        self._setitem.append((dic, name, oldval))
"""

DELITEM_OLD = """            self._setitem.append((dic, name, dic.get(name, NOTSET)))
            # Not all Mapping types support indexing, but MutableMapping doesn't support TypedDict
            del dic[name]  # type: ignore[attr-defined]
"""
DELITEM_NEW = """            oldval = dic.get(name, NOTSET)
            # Not all Mapping types support indexing, but MutableMapping doesn't support TypedDict
            del dic[name]  # type: ignore[attr-defined]
            self._setitem.append((dic, name, oldval))
"""


def apply_fix(path: str) -> None:
    with open(path, encoding="utf-8") as fh:
        src = fh.read()

    for old, new in (
        (DELATTR_OLD, DELATTR_NEW),
        (SETITEM_OLD, SETITEM_NEW),
        (DELITEM_OLD, DELITEM_NEW),
    ):
        count = src.count(old)
        if count != 1:
            sys.exit(
                f"fix_monkeypatch.py: pattern matched {count} times (expected 1); "
                f"the tree does not match the pinned parent. Not touching the file."
            )
        src = src.replace(old, new, 1)

    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: fix_monkeypatch.py <path-to-monkeypatch.py>")
    apply_fix(sys.argv[1])
    print("ok: undo bookkeeping fixed in", sys.argv[1])


if __name__ == "__main__":
    main()