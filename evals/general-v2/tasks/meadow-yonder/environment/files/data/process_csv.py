#!/usr/bin/env python3
"""process_csv.py - degenerate CSV normalizer (intentionally buggy).

Intended behaviour: every non-blank, non-comment input line is one "record",
and each record must be emitted as EXACTLY ONE output line, with every field
trimmed of surrounding whitespace and re-joined with a single comma.

There is a bug: the trailing newline on each source line is never stripped, so
it is carried through the final field and then a second newline is appended.
Each record therefore spills over onto an extra (blank) line - the newlines
accumulate across the file. Fix it so exactly one line is produced per record.

Usage: python3 process_csv.py <input.csv> <output.csv>
"""
import sys


def normalize(src, dst):
    with open(src, "r", encoding="utf-8") as fin, \
            open(dst, "w", encoding="utf-8") as fout:
        for line in fin:
            # BUG: we never strip `line`, so the source's trailing newline (and
            # any trailing whitespace) survives into the last field, and the
            # join + explicit "\n" below then append a SECOND newline.
            record = line
            if not record.strip() or record.lstrip().startswith("#"):
                continue
            fields = record.split(",")  # last field still carries "\n"
            fout.write(",".join(fields) + "\n")


if __name__ == "__main__":
    normalize(sys.argv[1], sys.argv[2])