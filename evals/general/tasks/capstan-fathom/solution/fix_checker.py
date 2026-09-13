#!/usr/bin/env python3
"""Oracle patch for capstan-fathom.

Applies the minimal, behavior-equivalent fix for the upstream bug to the
checked-out flake8 tree: _extract_syntax_information must only treat the
SyntaxError detail tuple as the legacy 4-element layout when it really is one
(Python 3.9 and earlier), and must read the physical line from its stable
absolute position in the tuple rather than from the last element (which on
Python 3.10+ is an end-offset integer, not text).
"""
import sys

OLD_CONDITION = (
    "        if column > 0 and token and isinstance(exception, SyntaxError):\n"
)
NEW_CONDITION = (
    "        if (\n"
    "            column > 0\n"
    "            and token\n"
    "            and isinstance(exception, SyntaxError)\n"
    "            and len(token) == 4  # Python 3.9 or earlier\n"
    "        ):\n"
)
OLD_LINE = (
    "            # See also: https://github.com/pycqa/flake8/issues/169\n"
    "            physical_line = token[-1]\n"
)
NEW_LINE = (
    "            # See also: https://github.com/pycqa/flake8/issues/169\n"
    "            # For Python 3.9 and earlier the tuple ends with the\n"
    "            # physical line; on 3.10+ the parser appends end-position\n"
    "            # fields after it, so read it from its stable absolute\n"
    "            # position in the tuple.\n"
    "            physical_line = token[3]\n"
)


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "/app/src/src/flake8/checker.py"
    with open(path, encoding="utf-8") as f:
        src = f.read()
    for old, new, what in (
        (OLD_CONDITION, NEW_CONDITION, "condition"),
        (OLD_LINE, NEW_LINE, "physical-line access"),
    ):
        if old not in src:
            print(f"ERROR: cannot locate the buggy {what} in {path}", file=sys.stderr)
            return 1
        src = src.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print(f"patched {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())