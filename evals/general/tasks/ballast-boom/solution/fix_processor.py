#!/usr/bin/env python3
"""Fix flake8's string redaction of escaped braces in f-strings.

The bug is in the logical-line construction path of the checked-out tree:
when Python 3.12 tokenizes an f-string, an escaped (doubled) curly brace
appears in an FSTRING_MIDDLE token in its *parsed* form (a single character)
while the token's end column and the next token's start column both account
for the raw double-brace span. The redaction step replaced the FSTRING_MIDDLE
text with one filler character per parsed character and kept the parsed end
column, so the next token's column bookkeeping was off by one per escaped
brace and raw characters from the physical line leaked into the logical line.

The fix redacts the raw span: each escaped brace counts for two filler
characters and the end column is extended by the same offset.

Usage: fix_processor.py [path-to-processor.py]
"""
import pathlib
import sys

DEFAULT = "/app/src/src/flake8/processor.py"

OLD = """            elif token_type == FSTRING_MIDDLE:  # pragma: >=3.12 cover
                text = "x" * len(text)
"""

NEW = """            elif token_type == FSTRING_MIDDLE:  # pragma: >=3.12 cover
                # A curly brace in an FSTRING_MIDDLE token must be an escaped
                # curly brace. Both 'text' and 'end' will account for the
                # escaped version of the token (i.e. a single brace) rather
                # than the raw double brace version, so we must counteract this
                brace_offset = text.count("{") + text.count("}")
                text = "x" * (len(text) + brace_offset)
                end = (end[0], end[1] + brace_offset)
"""


def main() -> int:
    path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else DEFAULT)
    src = path.read_text()
    if src.count(OLD) != 1:
        print(
            f"error: expected FSTRING_MIDDLE redaction block not found "
            f"exactly once in {path}",
            file=sys.stderr,
        )
        return 1
    if NEW in src:
        print(f"{path} already contains the fix; nothing to do")
        return 0
    path.write_text(src.replace(OLD, NEW))
    print(f"fixed {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())