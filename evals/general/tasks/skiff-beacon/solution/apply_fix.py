#!/usr/bin/env python3
"""Apply the minimal upstream fix for the skiff-beacon bug.

The Cython-accelerated uri.decode() let a literal '+' followed by two hex
digits fall into the percent-decoding branch when unquote_plus was False,
so decode('+00', unquote_plus=False) returned '\\x00' instead of '+00'.
The fix handles a '+' explicitly: it is only rewritten to a space when
unquote_plus is enabled, and otherwise copied through as-is, never reaching
the percent-decoding branch.

Usage: apply_fix.py /app/src/falcon/cyutil/uri.pyx
"""
import sys

BUGGY = """            if data[pos] == b'+' and unquote_plus:
                result[dst_start] = b' '
                dst_start += 1
                src_start += 1
                continue"""

FIXED = """            if data[pos] == b'+':
                # A literal plus is only rewritten to a space when
                # unquote_plus is enabled; otherwise it is preserved
                # as-is and must not be mistaken for a percent sequence.
                if unquote_plus:
                    result[dst_start] = b' '
                    dst_start += 1
                    src_start += 1
                continue"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: apply_fix.py <path-to-uri.pyx>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    with open(path, encoding='utf-8') as fh:
        text = fh.read()
    if BUGGY not in text:
        print(f"ERROR: the buggy '+'/unquote_plus branch was not found in "
              f"{path}; refusing to patch", file=sys.stderr)
        return 1
    fixed = text.replace(BUGGY, FIXED)
    if fixed == text:
        print("ERROR: patch produced no change", file=sys.stderr)
        return 1
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(fixed)
    print(f"patched {path}")
    return 0


if __name__ == '__main__':
    sys.exit(main())