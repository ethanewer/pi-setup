#!/usr/bin/env python3
"""Order ETL pipeline: processes the generated order dataset and writes output/summary.json."""
import json
import os
import random
import sys
import time

SEED = os.environ.get("SEED", "0")
HERE = os.path.dirname(os.path.abspath(__file__))


def gen_rows():
    r = random.Random(f"{SEED}:t2:data")
    rows = []
    for i in range(2000):
        amount = f"{r.uniform(1, 500):.2f}"
        if i == 1337:
            amount = "N/A"  # corrupt row leaked in from the upstream export
        qty = r.randint(1, 9)
        rows.append({"order_id": f"ord-{i:05d}", "amount": amount, "qty": str(qty)})
    return rows


def main():
    r = random.Random(f"{SEED}:t2:pace")
    per_row = r.uniform(0.03, 0.05)
    rows = gen_rows()
    total = 0.0
    processed = 0
    out_dir = os.path.join(HERE, "..", "output")
    os.makedirs(out_dir, exist_ok=True)
    start = time.time()
    print(f"[etl] pipeline starting on {len(rows)} rows")
    for i, row in enumerate(rows):
        amount = float(row["amount"])
        qty = int(row["qty"])
        total += amount * qty
        processed += 1
        if i % 250 == 0:
            print(f"[etl] processed {i}/{len(rows)} rows ({time.time() - start:.0f}s)")
        time.sleep(per_row)
    summary = {"rows": processed, "skipped": 0, "total": round(total, 2)}
    path = os.path.join(out_dir, "summary.json")
    with open(path, "w") as f:
        json.dump(summary, f)
    print(f"[etl] PIPELINE COMPLETE: wrote {path}")


if __name__ == "__main__":
    main()
