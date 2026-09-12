#!/usr/bin/env python3
"""Apply the upstream fix for bracket-cleat to the click checkout.

The bug: an option declared ``is_flag=False`` together with an explicit
``flag_value`` and a ``default`` refuses to be used without a value
("Option '--name' requires an argument.", exit code 2). An option that
carries a ``flag_value`` should be usable as a valueless flag: when it is
given by itself, its ``flag_value`` is used; an explicit value is still
saved by the parser when one is supplied.

In ``Option.__init__`` the valueless-flag allowance (the FLAG_NEEDS_VALUE
path in the parser) was turned off whenever a default was set, ignoring the
presence of ``flag_value``:

    self._flag_needs_value = self.default is UNSET

The upstream fix takes the ``flag_value`` into account:

    self._flag_needs_value = flag_value is not UNSET or self.default is UNSET

This script performs exactly that one-line behavioural change in
/app/src/src/click/core.py, matching the upstream fix byte for byte.
"""
import pathlib

CORE = pathlib.Path("/app/src/src/click/core.py")

OLD = "            self._flag_needs_value = self.default is UNSET\n"
NEW = (
    "            self._flag_needs_value = "
    "flag_value is not UNSET or self.default is UNSET\n"
)

text = CORE.read_text(encoding="utf-8")
count = text.count(OLD)
if count != 1:
    raise SystemExit(
        f"expected exactly one target line in {CORE}, found {count}; "
        "refusing to patch an unexpected tree"
    )
text = text.replace(OLD, NEW)
CORE.write_text(text, encoding="utf-8")
print("patched", CORE)