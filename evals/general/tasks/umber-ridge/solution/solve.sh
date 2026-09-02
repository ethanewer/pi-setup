#!/bin/bash
# Oracle for umber-ridge. Writes the generic, re-runnable deliverable
# /app/reconcile.py, then RUNS it on the visible sources to produce the two
# data deliverables (/app/mart.npy and /app/sheet.jsonl).
#
# reconcile.py is intentionally input-directory-agnostic: it takes a sources
# dir + an output dir as CLI args so the verifier can re-run it on hidden
# inputs. Literal /app paths for the deliverables.
set -euo pipefail

cat > /app/reconcile.py <<'PY'
#!/usr/bin/env python3
"""UmberRidge capital reconciliation exporter.

USAGE:
    python3 /app/reconcile.py <SOURCES_DIR> <OUT_DIR>

Reads <SOURCES_DIR>/clients.json, /deals.csv, /ledger.parquet and
/region_report.json; writes <OUT_DIR>/mart.npy and <OUT_DIR>/sheet.jsonl.
"""
import csv
import json
import os
import sys

import numpy as np
import pyarrow.parquet as pq

sys.path.insert(0, "/app")
from gridkit import CellGrid

REGIONS = ["NORTH", "SOUTH", "EAST", "WEST"]
REGION_ROWS = {"NORTH": 2, "SOUTH": 3, "EAST": 4, "WEST": 5}


def parse_records(srcdir):
    """Union the three heterogeneous sources into one canonical record stream."""
    rows = []

    with open(os.path.join(srcdir, "clients.json")) as fh:
        for rec in json.load(fh)["records"]:
            name = (str(rec["first_name"]) + " " + str(rec["last_name"])).strip()
            rows.append((int(rec["client_id"]), name, str(rec["branch"]),
                         float(rec["vp_balance"])))

    with open(os.path.join(srcdir, "deals.csv"), newline="") as fh:
        reader = csv.reader(fh)
        header = next(reader, None)
        for line in reader:
            if not line or all(not f for f in line):
                continue
            did, holder, territory, capital = [f.strip() for f in line]
            rows.append((int(did), holder, territory, float(capital)))

    table = pq.read_table(os.path.join(srcdir, "ledger.parquet")).to_pylist()
    for rec in table:
        rows.append((int(rec["cid"]), rec["label"], rec["zone"], float(rec["val"])))

    return rows


def region_sums(rows):
    agg = {r: 0.0 for r in REGIONS}
    for _cid, _name, region, bal in rows:
        if region in REGIONS:
            agg[region] += bal
    return {r: round(agg[r], 2) for r in REGIONS}


def main():
    srcdir, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)

    rows = parse_records(srcdir)
    reports = json.load(open(os.path.join(srcdir, "region_report.json")))["grand_totals"]
    sums = region_sums(rows)

    anomaly = None
    for r in REGIONS:
        if abs(sums[r] - reports[r]) > 1e-6:
            anomaly = r

    # ---- deliverable 1: unified mart (numpy structured array) ----
    order = sorted(rows, key=lambda t: t[0])
    mart = np.zeros(len(order),
                    dtype=[("client_id", "i8"), ("name", "U48"),
                           ("region", "U16"), ("balance_value", "f8")])
    for i, (cid, name, region, bal) in enumerate(order):
        mart[i] = (cid, name, region, bal)
    np.save(os.path.join(outdir, "mart.npy"), mart)

    # ---- deliverable 2: sheet populated through the CellGrid API ----
    sheet = CellGrid()
    for region in REGIONS:
        row = REGION_ROWS[region]
        sheet.set_cell("A%d" % row, region)
        sheet.set_cell("B%d" % row, sums[region])
        sheet.set_cell("C%d" % row, reports[region])
        sheet.set_cell("D%d" % row, "MISMATCH" if region == anomaly else "OK")
    sheet.set_cell("F2", reports[anomaly] if anomaly is not None else 0.0)
    sheet.export(os.path.join(outdir, "sheet.jsonl"))


if __name__ == "__main__":
    main()
PY
chmod +x /app/reconcile.py

# Produce the visible deliverables by RUNNING the real work.
python3 /app/reconcile.py /app/sources /app
echo "reconcile done: $(ls -1 /app/mart.npy /app/sheet.jsonl | wc -l) outputs"