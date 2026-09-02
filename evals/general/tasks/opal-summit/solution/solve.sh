#!/bin/bash
# Real oracle for opal-summit: write the solve.py program, then RUN it on the
# visible fixtures to produce /app/report.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/report.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import csv
import json
import sys
from datetime import date


def read_rows(path):
    """Yield trimmed, non-empty CSV rows."""
    with open(path, "r", encoding="utf-8", newline="") as fh:
        for row in csv.reader(fh):
            if not row or all(c.strip() == "" for c in row):
                continue
            yield [c.strip() for c in row]


def parse_period(path):
    bounds = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            key, _, value = line.partition("=")
            bounds[key.strip()] = value.strip()
    return date.fromisoformat(bounds["from"]), date.fromisoformat(bounds["to"])


def parse_int(s):
    try:
        return int(s)
    except ValueError:
        return None


def parse_dec(s):
    try:
        return float(s)
    except ValueError:
        return None


def parse_date(s):
    try:
        return date.fromisoformat(s)
    except ValueError:
        return None


def main():
    orders_path = sys.argv[1] if len(sys.argv) > 1 else "/app/orders.csv"
    products_path = sys.argv[2] if len(sys.argv) > 2 else "/app/products.csv"
    period_path = sys.argv[3] if len(sys.argv) > 3 else "/app/period.txt"
    out_path = sys.argv[4] if len(sys.argv) > 4 else "/app/report.json"

    lo, hi = parse_period(period_path)

    catalog = {}
    rows = list(read_rows(products_path))
    for row in rows[1:]:
        if len(row) < 3:
            continue
        pid, name, cat = row[0], row[1], row[2]
        catalog[pid] = {"product_id": pid, "product_name": name,
                        "category": cat, "units": 0, "orders": 0,
                        "revenue": 0.0}

    total_revenue = 0.0
    for row in list(read_rows(orders_path))[1:]:
        if len(row) < 5:
            continue
        _oid, pid, qty_s, price_s, date_s = row[:5]
        qty = parse_int(qty_s)
        price = parse_dec(price_s)
        d = parse_date(date_s)
        if qty is None or price is None or d is None:
            continue
        if not (lo <= d <= hi):
            continue
        if pid not in catalog:
            continue
        amount = qty * price
        entry = catalog[pid]
        entry["units"] += qty
        entry["orders"] += 1
        entry["revenue"] += amount
        total_revenue += amount

    ranked = sorted(catalog.values(),
                    key=lambda e: (-e["revenue"], e["product_id"]))
    for entry in ranked:
        entry["revenue"] = round(entry["revenue"], 2)

    report = {
        "period": {"from": lo.isoformat(), "to": hi.isoformat()},
        "products": ranked,
        "top_products": [e["product_id"] for e in ranked[:3]],
        "total_revenue": round(total_revenue, 2),
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate the output.
python3 "$SOLVER" /app/orders.csv /app/products.csv /app/period.txt "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
