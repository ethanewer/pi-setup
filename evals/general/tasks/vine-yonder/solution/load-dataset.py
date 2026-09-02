#!/usr/bin/env python3
"""load-dataset.py -- pull the configured config+reserved-split slice of a repo.

Usage:
    python3 /app/load-dataset.py [HUB_URL]

Default HUB_URL is the shipped hub:
    http://127.0.0.1:9000/hub/rose-orchard

Each hub dataset exposes manifest.json which declares its release "config"s,
the splits inside them, and marks one config as required plus one split as the
reserved reporting split (see README.md). This loader discovers that config id
and reserved split, fetches exactly that slice, and aggregates a numeric over a
named field. Writes /app/dataset-report.json.
"""
import csv
import io
import json
import sys
import urllib.request

OUT = "/app/dataset-report.json"
DEFAULT_HUB = "http://127.0.0.1:9000/hub/rose-orchard"


def get_json(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def get_text(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.read().decode("utf-8")


def compute_total(csv_text, field):
    """Sum valid numeric cells in `field`; blank, non-numeric cells and trailing
    blank lines are skipped.  Identifies the column by header name (first row
    whose cells contain the field label). Return (solid_rows, total)."""
    reader = csv.reader(io.StringIO(csv_text))
    rows_iter = iter(reader)
    col = 0
    found_header = False
    for row in rows_iter:
        if not row:
            continue
        cells = [c.strip() for c in row]
        if field in cells:
            col = cells.index(field)
            found_header = True
            break
    # if no header row names the field, assume it is column 0
    if not found_header:
        col = 0
        rows_iter = iter(csv.reader(io.StringIO(csv_text)))
        next(rows_iter, None)
    total = 0.0
    count = 0
    for row in rows_iter:
        if not row or not row[0].strip():
            continue
        if col >= len(row):
            continue
        cell = (row[col] or "").strip()
        if cell == "":
            continue
        try:
            total += float(cell)
        except (TypeError, ValueError):
            continue  # non-numeric -> skip
        count += 1
    return count, total


def main():
    hub = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_HUB
    hub = hub.rstrip("/")
    manifest = get_json(hub + "/manifest.json")
    ds = manifest.get("dataset")
    cfg = manifest["required_config"]
    split = manifest["required_split"]
    field = manifest["field"]
    text = get_text("%s/%s/%s.csv" % (hub, cfg, split))
    rows, total = compute_total(text, field)
    report = {
        "name": ds,
        "config": cfg,
        "split": split,
        "field": field,
        "rows": rows,
        "total": total,
    }
    with open(OUT, "w") as f:
        json.dump(report, f, indent=1)
        f.write("\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()