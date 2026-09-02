"""Console entry point for the ``ledger-check`` command.

Reads a single amount line from stdin and prints the normalized cents count.
On malformed input it prints a diagnostic to stderr and exits non-zero.
"""
import sys

from . import normalize_amount


def main(argv=None):
    line = sys.stdin.readline()
    if line.endswith("\n"):
        line = line[:-1]
    if line.endswith("\r"):
        line = line[:-1]
    try:
        print(normalize_amount(line))
    except ValueError as exc:
        print(f"ledger-check: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())