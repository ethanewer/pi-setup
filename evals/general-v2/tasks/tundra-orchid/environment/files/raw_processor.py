#!/usr/bin/env python3
"""Buggy CSV processor: every output record carries an accumulated trailing
newline, so the produced file has ONE EXTRA BLANK physical line per record.

Usage: python3 raw_processor.py <input.csv> <output.csv>
"""
import sys


def main():
    if len(sys.argv) != 3:
        print("usage: raw_processor.py <input.csv> <output.csv>", file=sys.stderr)
        sys.exit(2)
    infile, outfile = sys.argv[1], sys.argv[2]

    records = []
    with open(infile, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip("\n")
            if line.strip() == "":
                continue
            cols = line.split(",")
            if len(cols) != 2:
                continue
            name = cols[0].strip().lower()
            qty = cols[1]  # BUG: no strip() -> keeps trailing newline / CR
            if name == "" or qty == "":
                continue
            records.append((name, qty))

    with open(outfile, "w", encoding="utf-8") as fh:
        for name, qty in records:
            fh.write(name + "," + qty + "\n")


if __name__ == "__main__":
    main()