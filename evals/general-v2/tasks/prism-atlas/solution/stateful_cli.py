#!/usr/bin/env python3
"""stateful_cli.py — persistent rolling counter (prism parts 2 & 3).

Usage:
    python3 stateful_cli.py <delta> [state_file]

Accumulates a running integer total in a state file. Each run:
  1. reads the current value from <state_file> (default
     /app/state/state.txt). If the file is missing/empty it starts from 0;
     the value is the integer text in the file with surrounding whitespace
     stripped.
  2. adds <delta> (any integer, may be negative),
  3. writes the new value, as plain base-10 decimal text plus a newline, back
     to the SAME state file (written atomically), and
  4. prints the new value to stdout.

The tool NEVER resets to a fixed initial value; every invocation continues
from whatever the on-disk state file currently holds.
"""
import os
import sys


DEFAULT_STATE = "/app/state/state.txt"


def read_value(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read().strip()
    except OSError:
        text = ""
    if not text:
        return 0
    try:
        return int(text)
    except ValueError:
        # tolerate a trailing integer on a partially-edited line: take the
        # last whitespace-separated token that parses as an integer.
        tokens = text.split()
        for tok in reversed(tokens):
            try:
                return int(tok)
            except ValueError:
                continue
        return 0


def write_value(path, value):
    directory = os.path.dirname(path)
    if directory and not os.path.isdir(directory):
        os.makedirs(directory, exist_ok=True)
    tmp = path + ".tmp%d" % os.getpid()
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(str(value) + "\n")
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def main(argv):
    if not argv:
        sys.stderr.write("usage: stateful_cli.py DELTA [STATE_FILE]\n")
        return 2
    delta_arg = argv[0]
    state_file = argv[1] if len(argv) > 1 else DEFAULT_STATE
    delta = int(delta_arg)

    current = read_value(state_file)
    new_value = current + delta
    write_value(state_file, new_value)
    print(new_value)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))