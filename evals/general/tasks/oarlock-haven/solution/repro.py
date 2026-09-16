#!/usr/bin/env python3
"""Reproduction for a pytest monkeypatch bug.

If a monkeypatch mutation fails (setitem/delitem on an immutable mapping,
delattr of an attribute that cannot be removed), pytest must not record an
undo entry for the operation that never happened: calling undo() afterwards
must be a harmless no-op.

Exit status: 0 iff the behaviour is correct; nonzero while the bug is present
(the undo() call re-raises the original TypeError/AttributeError).
"""

import sys
from types import MappingProxyType


def main() -> int:
    from _pytest.monkeypatch import MonkeyPatch

    failures = []

    # --- case 1: setitem on an immutable mapping proxy fails (TypeError) ----
    mapping = MappingProxyType({"x": 1})
    mp1 = MonkeyPatch()
    try:
        mp1.setitem(mapping, "x", 2)
    except TypeError:
        pass
    else:
        failures.append("setitem on a mapping proxy should have raised")
    try:
        mp1.undo()  # must be a no-op: no mutation happened
    except TypeError as exc:
        failures.append(f"undo() after failed setitem re-raised: {exc!r}")
    assert mapping["x"] == 1

    # --- case 2: delattr of a non-removable slot attribute fails ------------
    class A:
        __slots__ = ()
        x = 1

    a = A()
    mp2 = MonkeyPatch()
    try:
        mp2.delattr(a, "x")
    except AttributeError:
        pass
    else:
        failures.append("delattr of a slot attribute should have raised")
    try:
        mp2.undo()  # must be a no-op: no mutation happened
    except AttributeError as exc:
        failures.append(f"undo() after failed delattr re-raised: {exc!r}")
    assert a.x == 1

    if failures:
        for msg in failures:
            print(f"FAIL: {msg}")
        return 1
    print("OK: undo() was a quiet no-op after each failed mutation")
    return 0


if __name__ == "__main__":
    sys.exit(main())