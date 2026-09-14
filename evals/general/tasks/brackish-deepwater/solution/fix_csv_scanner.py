#!/usr/bin/env python3
"""Apply the minimal upstream fix for the brackish-deepwater bug.

Parallel CSV reading of a file whose lines end with the three-byte sequence
CR CR LF ('\\r\\r\\n') double-counts rows near buffer boundaries. In
StringValueScanner::ProcessOverBufferValue, when the newline-consuming
CARRY_ON loop at the end of a buffer consumed characters without adding a
row, the scanner fell through to the "second buffer" loop and processed the
next row's data, while the previous buffer's scanner had already counted that
row. Result: the row is counted twice, so a 10,000-row file yields 10,002
rows (buffer_size=4096), 10,004 at buffer_size=2048, and so on. The
sequential reader is unaffected.

The fix records the position before the carry loop and returns early when
all three conditions hold: the carry loop consumed newline characters but
added no row (over_buffer_string is empty and buffer_pos advanced), the row
was fully counted by the previous buffer (last_position.buffer_pos overshoots
the previous buffer), and the first consumed character was '\\r' (so
'\\r\\r\\n' is handled while plain '\\r\\n' endings are unaffected).

The inserted guard is the same one the upstream fix added.

Usage: fix_csv_scanner.py /app/src
"""
import sys
from pathlib import Path

FILE = Path("src/execution/operator/csv_scanner/scanner/string_value_scanner.cpp")

ANCHOR_BEFORE = "\t\t} else {\n\t\t\twhile (iterator.pos.buffer_pos < cur_buffer_handle->actual_size &&\n"
INSERT_BEFORE = (
    "\t\t} else {\n"
    "\t\t\tidx_t pre_carry_pos = iterator.pos.buffer_pos;\n"
    "\t\t\twhile (iterator.pos.buffer_pos < cur_buffer_handle->actual_size &&\n"
)

ANCHOR_AFTER = (
    "\t\t\t\tstate_machine->Transition(states, buffer_handle_ptr[iterator.pos.buffer_pos]);\n"
    "\t\t\t\titerator.pos.buffer_pos++;\n"
    "\t\t\t}\n"
    "\t\t}\n"
    "\t}\n"
    "\t// second buffer\n"
)
INSERT_AFTER = (
    "\t\t\t\tstate_machine->Transition(states, buffer_handle_ptr[iterator.pos.buffer_pos]);\n"
    "\t\t\t\titerator.pos.buffer_pos++;\n"
    "\t\t\t}\n"
    "\t\t\t// If we consumed newline characters but didn't add a row, and the previous\n"
    "\t\t\t// buffer's scanner already fully counted the row (last_position overshoots the\n"
    "\t\t\t// buffer), return early to avoid double-counting the next row. This handles\n"
    "\t\t\t// \\r\\r\\n line endings where the first \\r triggered AddRow in the previous\n"
    "\t\t\t// buffer and the remaining \\r\\n is here. We check that the first consumed\n"
    "\t\t\t// character is \\r (not \\n) to avoid false-positives for \\r\\n line endings\n"
    "\t\t\t// where \\r was at the end of the previous buffer and \\n is here.\n"
    "\t\t\tif (over_buffer_string.empty() && iterator.pos.buffer_pos > pre_carry_pos &&\n"
    "\t\t\t    result.last_position.buffer_pos > previous_buffer_handle->actual_size &&\n"
    "\t\t\t    buffer_handle_ptr[pre_carry_pos] == '\\r') {\n"
    "\t\t\t\treturn;\n"
    "\t\t\t}\n"
    "\t\t}\n"
    "\t}\n"
    "\t// second buffer\n"
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_csv_scanner.py <path-to-duckdb-src>")
        return 2
    src = Path(sys.argv[1])
    path = src / FILE
    if not path.is_file():
        print(f"ERROR: {FILE} not found under {src}", file=sys.stderr)
        return 1
    text = path.read_text(encoding="utf-8")
    if "pre_carry_pos" in text:
        print("already fixed (pre_carry_pos present); nothing to do")
        return 0
    if text.count(ANCHOR_BEFORE) != 1:
        print("ERROR: anchor 1 not unique", file=sys.stderr)
        return 1
    if text.count(ANCHOR_AFTER) != 1:
        print("ERROR: anchor 2 not unique", file=sys.stderr)
        return 1
    text = text.replace(ANCHOR_BEFORE, INSERT_BEFORE, 1)
    text = text.replace(ANCHOR_AFTER, INSERT_AFTER, 1)
    path.write_text(text, encoding="utf-8")
    print("patched string_value_scanner.cpp")
    return 0


if __name__ == "__main__":
    sys.exit(main())