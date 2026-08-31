#!/bin/bash
# Real oracle for hazel-quay: write the solve.py program, then RUN it on the
# visible fixtures to produce /app/answer.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/answer.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
import json
import re
import sys
from datetime import date


def _is_pos_int(s):
    return bool(re.fullmatch(r"\d+", s)) and int(s) > 0


def _is_money(s):
    return bool(re.fullmatch(r"\d+(\.\d{1,2})?", s))


def load_period(path):
    bounds = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            key, _, value = line.partition("=")
            bounds[key.strip()] = value.strip()
    return date.fromisoformat(bounds["from"]), date.fromisoformat(bounds["to"])


def main():
    items_path, returns_path, period_path, out_path = sys.argv[1:5]
    lo, hi = load_period(period_path)

    malformed_items = 0
    malformed_returns = 0
    unmatched_returns = 0
    orders = set()
    prod = {}

    data_rows = []
    header_seen = False
    with open(items_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            parts = [p.strip() for p in line.split(",")]
            if len(parts) == 1 and parts[0] == "":
                continue
            if not header_seen:
                header_seen = True
                continue
            if len(parts) != 5:
                malformed_items += 1
                continue
            oid, d, pid, units, price = parts
            if not (oid and pid and re.fullmatch(r"\d{4}-\d{2}-\d{2}", d)
                    and _is_pos_int(units) and _is_money(price)):
                malformed_items += 1
                continue
            dt = date.fromisoformat(d)
            data_rows.append((oid, dt, pid, int(units), float(price)))

    for oid, dt, pid, units, price in data_rows:
        if not (lo <= dt <= hi):
            continue
        orders.add(oid)
        g = prod.setdefault(pid, {"units_gross": 0, "gross": 0.0,
                                  "returned": 0.0, "units_ret": 0})
        g["units_gross"] += units
        g["gross"] += units * price

    in_range = [(oid, pid, price) for oid, dt, pid, units, price in data_rows
                if lo <= dt <= hi]

    rheader = False
    with open(returns_path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            parts = [p.strip() for p in line.split(",")]
            if len(parts) == 1 and parts[0] == "":
                continue
            if not rheader:
                rheader = True
                continue
            if len(parts) != 4:
                malformed_returns += 1
                continue
            rid, oid, pid, units = parts
            if not (rid and oid and pid and not re.search(r"\s", rid)
                    and _is_pos_int(units)):
                malformed_returns += 1
                continue
            units = int(units)
            match = next((r for r in in_range if r[0] == oid and r[1] == pid), None)
            if match is None:
                unmatched_returns += 1
                continue
            g = prod.setdefault(match[1], {"units_gross": 0, "gross": 0.0,
                                           "returned": 0.0, "units_ret": 0})
            g["returned"] += units * match[2]
            g["units_ret"] += units

    products = {}
    for pid in sorted(prod):
        g = prod[pid]
        products[pid] = {
            "units_gross": g["units_gross"],
            "gross": round(g["gross"], 2),
            "returned": round(g["returned"], 2),
            "net": round(g["gross"] - g["returned"], 2),
            "units_net": g["units_gross"] - g["units_ret"],
        }
    total_gross = round(sum(g["gross"] for g in prod.values()), 2)
    total_returned = round(sum(g["returned"] for g in prod.values()), 2)
    total_net = round(total_gross - total_returned, 2)
    top = [pid for pid, _ in sorted(products.items(),
                                    key=lambda kv: (-kv[1]["net"], kv[0]))][:3]

    answer = {
        "period": {"from": lo.isoformat(), "to": hi.isoformat()},
        "total_gross": total_gross,
        "total_returned": total_returned,
        "total_net": total_net,
        "orders_in_range": len(orders),
        "malformed_line_items": malformed_items,
        "malformed_returns": malformed_returns,
        "unmatched_returns": unmatched_returns,
        "products": products,
        "top_products": top,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(answer, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixtures to generate the output.
python3 "$SOLVER" /app/lineitems.csv /app/returns.csv /app/period.txt "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
