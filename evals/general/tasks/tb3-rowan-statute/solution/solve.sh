#!/bin/bash
# Oracle for tb3-rowan-statute: installs the declaration builder
# (build_declaration.py) and runs it on the visible workdir /app, producing
# the declaration and the validation report. The script is fully generic
# (takes a workdir argument) and deterministic. Never reads /tests.
set -eu

cat > /app/build_declaration.py <<'PY'
#!/usr/bin/env python3
"""Rowan Statute compliance declaration builder.

Usage: python3 build_declaration.py <workdir>

Reads <workdir>/transactions.csv, <workdir>/codes/countries.json,
<workdir>/codes/commodities.json and <workdir>/params.json and writes
<workdir>/declaration.csv and <workdir>/validation_report.json.
Pure stdlib, fully deterministic.
"""
import csv
import json
import os
import re
import sys
from datetime import datetime
from decimal import Decimal

DIRECTIONS = ("dispatch", "arrival")
HEADER = "direction,partner_country,commodity_code,value_eur,quantity_kg"
VALUE_OK = re.compile(r"^\d+(\.\d{1,2})?$")
QTY_OK = re.compile(r"^\d+(\.\d{1,3})?$")


def main(argv):
    if len(argv) != 2:
        print("usage: build_declaration.py <workdir>", file=sys.stderr)
        return 1
    try:
        build(argv[1])
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print("build_declaration.py: %s" % exc, file=sys.stderr)
        return 1
    return 0


def build(workdir):
    with open(os.path.join(workdir, "codes", "countries.json"),
              encoding="utf-8") as fh:
        country_codes = set(json.load(fh)["codes"])
    with open(os.path.join(workdir, "codes", "commodities.json"),
              encoding="utf-8") as fh:
        commodity_table = json.load(fh)["codes"]
    with open(os.path.join(workdir, "params.json"),
              encoding="utf-8") as fh:
        parameters = json.load(fh)

    threshold_cents = {}
    for direction in DIRECTIONS:
        threshold_cents[direction] = int(
            Decimal(str(parameters["exemption_threshold_eur"][direction])) * 100)

    data_rows = read_data_rows(os.path.join(workdir, "transactions.csv"))

    rejected = []
    valid = []
    for cells in data_rows:
        reasons = classify(cells, country_codes, commodity_table)
        if reasons:
            rejected.append({"txn_id": cells[0], "reasons": reasons})
        else:
            valid.append(cells)

    totals = {}  # (direction, country, commodity) -> [cents, milli_kg]
    for cells in valid:
        direction = cells[2]
        country = cells[3]
        commodity = cells[4]
        cents = int(Decimal(cells[5]) * 100)
        milli = int(Decimal(cells[6]) * 1000)
        bucket = totals.setdefault((direction, country, commodity), [0, 0])
        bucket[0] += cents
        bucket[1] += milli

    kept = []
    for (direction, country, commodity), (cents, milli) in totals.items():
        if cents >= threshold_cents[direction]:
            kept.append((direction, country, commodity, cents, milli))
    kept.sort(key=lambda row: (row[0], row[1], row[2]))

    with open(os.path.join(workdir, "declaration.csv"), "w",
              newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(HEADER.split(","))
        for direction, country, commodity, cents, milli in kept:
            writer.writerow([
                direction, country, commodity,
                "%d.%02d" % (cents // 100, cents % 100),
                "%d.%03d" % (milli // 1000, milli % 1000),
            ])

    rejected.sort(key=lambda entry: entry["txn_id"])  # stable by txn_id
    report = {"rejected": rejected}
    with open(os.path.join(workdir, "validation_report.json"), "w",
              encoding="utf-8") as fh:
        json.dump(report, fh, separators=(",", ":"))
        fh.write("\n")


def read_data_rows(path):
    """All data rows after the header line; blank lines are ignored."""
    rows = []
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.reader(fh)
        try:
            next(reader)  # header line
        except StopIteration:
            return rows
        for cells in reader:
            if not any((cell or "").strip() for cell in cells):
                continue
            rows.append(cells)
    return rows


def classify(cells, country_codes, commodity_table):
    if len(cells) != 7:
        return ["MALFORMED_ROW"]
    _txn, date, direction, country, commodity, value, qty = cells
    reasons = []
    if direction not in DIRECTIONS:
        reasons.append("INVALID_DIRECTION")
    if country not in country_codes:
        reasons.append("UNKNOWN_COUNTRY")
    if commodity not in commodity_table:
        reasons.append("UNKNOWN_COMMODITY")
    else:
        entry = commodity_table[commodity]
        if not (isinstance(entry, dict)
                and isinstance(entry.get("unit"), str)
                and entry["unit"] != ""):
            reasons.append("UNKNOWN_COMMODITY")
    try:
        datetime.strptime(date, "%Y-%m-%d")
    except (TypeError, ValueError):
        reasons.append("INVALID_DATE")
    if not VALUE_OK.fullmatch(value):
        reasons.append("INVALID_VALUE")
    if not QTY_OK.fullmatch(qty):
        reasons.append("INVALID_QUANTITY")
    return reasons


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

chmod 0755 /app/build_declaration.py

python3 /app/build_declaration.py /app

echo "oracle: deliverables produced"
ls -l /app/build_declaration.py /app/declaration.csv /app/validation_report.json
echo "--- declaration.csv ---"
cat /app/declaration.csv
echo "--- validation_report.json ---"
cat /app/validation_report.json