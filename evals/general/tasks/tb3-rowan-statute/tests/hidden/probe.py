#!/usr/bin/env python3
"""Independent verifier for tb3-rowan-statute.

Recomputes declaration.csv and validation_report.json from raw inputs, checks
the visible deliverables /app/declaration.csv and /app/validation_report.json,
then EXECUTES /app/build_declaration.py on a copy of the visible workdir and on
every hidden workdir under /tests/hidden, comparing each output against its own
recomputation. Exits 0 iff everything matches; never crashes on malformed agent
output (records a failure instead).
"""
import csv
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from decimal import Decimal

APP = "/app"
HIDDEN = "/tests/hidden"
SCRIPT = "/app/build_declaration.py"

VALUE_OK = re.compile(r"^\d+(\.\d{1,2})?$")
QTY_OK = re.compile(r"^\d+(\.\d{1,3})?$")


def main():
    failures = []
    try:
        want_decl, want_report = recompute(APP)
        check_csv("/app/declaration.csv", want_decl,
                  "visible /app/declaration.csv", failures)
        check_json("/app/validation_report.json", want_report,
                   "visible /app/validation_report.json", failures)
    except Exception as exc:  # noqa: BLE001
        failures.append("recompute of /app failed: %r" % exc)

    vis_run = "/tmp/rowan_visible_run"
    if prepare_run(vis_run, APP):
        run_case(SCRIPT, vis_run, recompute(APP), "visible execute", failures)
    else:
        failures.append("cannot stage visible workdir copy")

    if not os.path.isdir(HIDDEN):
        failures.append("no hidden cases directory")
    else:
        cases = sorted(n for n in os.listdir(HIDDEN)
                       if os.path.isdir(os.path.join(HIDDEN, n)))
        if not cases:
            failures.append("no hidden case directories under %s" % HIDDEN)
        for name in cases:
            staged = "/tmp/rowan_hidden_%s" % re.sub(r"[^A-Za-z0-9_.-]", "_", name)
            if not prepare_run(staged, os.path.join(HIDDEN, name)):
                failures.append("cannot stage hidden case '%s'" % name)
                continue
            try:
                want_decl, want_report = recompute(staged)
            except Exception as exc:  # noqa: BLE001
                failures.append("recompute of hidden '%s' failed: %r" % (name, exc))
                continue
            run_case(SCRIPT, staged, (want_decl, want_report),
                     "hidden '%s'" % name, failures)

    print("verify failures: %d" % len(failures))
    for item in failures:
        print("  - %s" % item)
    return 1 if failures else 0


def prepare_run(dst, src):
    """Stage a workdir copy containing only the four raw inputs."""
    try:
        shutil.rmtree(dst, ignore_errors=True)
        os.makedirs(os.path.join(dst, "codes"), exist_ok=True)
        shutil.copy2(os.path.join(src, "transactions.csv"), dst)
        shutil.copy2(os.path.join(src, "codes", "countries.json"),
                     os.path.join(dst, "codes"))
        shutil.copy2(os.path.join(src, "codes", "commodities.json"),
                     os.path.join(dst, "codes"))
        shutil.copy2(os.path.join(src, "params.json"), dst)
        return True
    except OSError:
        return False


def run_case(script, workdir, want, label, failures):
    try:
        proc = subprocess.run(["python3", script, workdir],
                              capture_output=True, text=True, timeout=60)
    except Exception as exc:  # noqa: BLE001
        failures.append("%s: executing /app/build_declaration.py raised %r"
                        % (label, exc))
        return
    if proc.returncode != 0:
        failures.append("%s: /app/build_declaration.py exited %d (%s)"
                        % (label, proc.returncode,
                           (proc.stderr or "").strip()[:200]))
        return
    check_csv(os.path.join(workdir, "declaration.csv"), want[0],
              "%s declaration.csv" % label, failures)
    check_json(os.path.join(workdir, "validation_report.json"), want[1],
               "%s validation_report.json" % label, failures)


def check_csv(path, want_rows, label, failures):
    try:
        with open(path, newline="", encoding="utf-8") as fh:
            got = [list(r) for r in csv.reader(fh)]
    except OSError as exc:
        failures.append("%s unreadable: %s" % (label, exc))
        return
    if not got or got[0] != "direction,partner_country,commodity_code,value_eur,quantity_kg".split(","):
        failures.append("%s header mismatch: %r" % (label, got[0] if got else None))
        return
    if got[1:] != want_rows[1:]:
        failures.append("%s row content mismatch" % label)


def check_json(path, want, label, failures):
    try:
        with open(path, encoding="utf-8") as fh:
            got = json.load(fh)
    except Exception as exc:  # noqa: BLE001
        failures.append("%s unreadable: %s" % (label, exc))
        return
    if got != want:
        failures.append("%s content mismatch" % label)


def recompute(root):
    """Independent reimplementation of the documented pipeline."""
    def read_json(rel):
        with open(os.path.join(root, rel), encoding="utf-8") as fh:
            return json.load(fh)

    country_codes = set(read_json("codes/countries.json")["codes"])
    commodity_table = read_json("codes/commodities.json")["codes"]
    parameters = read_json("params.json")
    threshold_cents = {}
    for direction in ("dispatch", "arrival"):
        threshold_cents[direction] = int(
            Decimal(str(parameters["exemption_threshold_eur"][direction])) * 100)

    records = []
    with open(os.path.join(root, "transactions.csv"),
              newline="", encoding="utf-8") as fh:
        reader = csv.reader(fh)
        try:
            next(reader)  # header line
        except StopIteration:
            pass
        for cells in reader:
            if not any((cell or "").strip() for cell in cells):
                continue
            records.append(cells)

    rejected = []
    totals = {}
    for cells in records:
        reasons = classify(cells, country_codes, commodity_table)
        if reasons:
            rejected.append({"txn_id": cells[0], "reasons": reasons})
            continue
        _, _, direction, country, commodity, value, qty = cells
        cents = int(Decimal(value) * 100)
        milli = int(Decimal(qty) * 1000)
        bucket = totals.setdefault((direction, country, commodity), [0, 0])
        bucket[0] += cents
        bucket[1] += milli

    kept = []
    for (direction, country, commodity), (cents, milli) in totals.items():
        if cents >= threshold_cents[direction]:
            kept.append((direction, country, commodity, cents, milli))
    kept.sort(key=lambda row: (row[0], row[1], row[2]))

    rows = [["direction", "partner_country", "commodity_code",
             "value_eur", "quantity_kg"]]
    for direction, country, commodity, cents, milli in kept:
        rows.append([direction, country, commodity,
                     "%d.%02d" % (cents // 100, cents % 100),
                     "%d.%03d" % (milli // 1000, milli % 1000)])

    rejected.sort(key=lambda entry: entry["txn_id"])  # stable
    return rows, {"rejected": rejected}


def classify(cells, country_codes, commodity_table):
    if len(cells) != 7:
        return ["MALFORMED_ROW"]
    _txn, date, direction, country, commodity, value, qty = cells
    reasons = []
    if direction not in ("dispatch", "arrival"):
        reasons.append("INVALID_DIRECTION")
    if country not in country_codes:
        reasons.append("UNKNOWN_COUNTRY")
    entry = commodity_table.get(commodity)
    if entry is None or not (isinstance(entry, dict)
                             and isinstance(entry.get("unit"), str)
                             and entry["unit"]):
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
    sys.exit(main())