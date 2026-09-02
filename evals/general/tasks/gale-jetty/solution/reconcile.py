#!/usr/bin/env python3
"""Gale-Jetty close-out reconcile driver.

Pipeline (operates on --input, writes under --output; defaults to /app):

  1. Classify each file under <input>/inbox: a file whose first non-empty line
     is exactly "INVOICE" is an invoice, every other file is "other". Move each
     into <output>/ledger/invoice or <output>/ledger/other, leaving inbox empty.
  2. Iterate EVERY row of <input>/masks.csv (never a sample). For each row write
     one prompt line to <output>/prompts.txt and build an 8x10 (grid from
     config.json) SAM-style bool mask from the normalized cell rectangle
     (r0,c0)-(r1,c1); the per-row masks are persisted as <output>/inference.npz
     (key "masks", shape (N, R, C)).
  3. Ask the extraction engine (/app/extract.py) to parse the heterogeneous
     ledger (<input>/hx: csv/json/parquet -> one schema) and write the
     recovered matrix <output>/mart.npy (N x 3, masks.csv invoice order,
     [amount, fee, (amount+fee)*ITERATIONS] with ITERATIONS imported).
  4. Write the close-out sheet <output>/sheet.jsonl (exact cell addresses on
     sheet "GJ": A<k>=amount, B<k>=fee, C<k>=cost per invoice row k=i+1, plus
     TOTAL and NOTE records).
  5. Fiscal cross-check: compare the ledger fee with masks.csv expected_fee;
     the single inconsistent invoice id goes to <output>/mismatch.txt ("NONE"
     when none, comma-joined when several).
  6. Filter/rank candidate descriptors (`<input>/candidates.json`) within an
     inclusive tolerance of the target (config.json close.target/tolerance),
     sorted by normalized proximity score 1/(1+distance), ties by id; the
     structured result is written to <output>/ranked.json.

Runnable: python3 /app/reconcile.py [--input DIR] [--output DIR]
"""
import argparse
import csv
import json
import os
import shutil
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import extract  # noqa: E402  the runnable extraction engine
from compute_parallel import ITERATIONS  # noqa: E402

HEADER_TOKEN = "INVOICE"


def classify(text):
    first = (text.splitlines() or [""])[0].strip()
    return "invoice" if first == HEADER_TOKEN else "other"


def load_config(indir):
    cfg = {"grid": {"rows": 8, "cols": 10}, "close": {"target": 50.0, "tolerance": 25.0}}
    path = os.path.join(indir, "config.json")
    if os.path.exists(path):
        try:
            cfg.update(json.load(open(path)))
        except Exception:
            pass
    return cfg


def read_masks(path):
    rows = []
    if not os.path.exists(path):
        return rows
    with open(path) as fh:
        for r in csv.DictReader(fh):
            rows.append({
                "invoice_id": str(r["invoice_id"]).strip(),
                "r0": int(r["row0"]), "c0": int(r["col0"]),
                "r1": int(r["row1"]), "c1": int(r["col1"]),
                "expected_fee": float(r["expected_fee"]),
            })
    return rows


def move_docs(indir, outdir):
    inbox = os.path.join(indir, "inbox")
    led = os.path.join(outdir, "ledger")
    for bucket in ("invoice", "other"):
        # Idempotent: never delete existing classified output, only append.
        os.makedirs(os.path.join(led, bucket), exist_ok=True)
    if os.path.isdir(inbox):
        for fn in sorted(os.listdir(inbox)):
            path = os.path.join(inbox, fn)
            if not os.path.isfile(path):
                continue
            with open(path, encoding="utf-8", errors="replace") as fh:
                content = fh.read()
            cls = classify(content)
            shutil.move(path, os.path.join(led, cls, fn))


def build_masks(indir, outdir, cfg):
    masks = read_masks(os.path.join(indir, "masks.csv"))
    rows = int(cfg["grid"]["rows"])
    cols = int(cfg["grid"]["cols"])
    prompts = []
    grids = []
    for i, m in enumerate(masks):
        r0, r1 = min(m["r0"], m["r1"]), max(m["r0"], m["r1"])
        c0, c1 = min(m["c0"], m["c1"]), max(m["c0"], m["c1"])
        g = np.zeros((rows, cols), dtype=bool)
        if rows and cols:
            g[r0:r1 + 1, c0:c1 + 1] = True
        grids.append(g)
        prompts.append("prompt[%d] invoice=%s rect=(%d,%d,%d,%d)"
                       % (i + 1, m["invoice_id"], r0, c0, r1, c1))
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "prompts.txt"), "w") as fh:
        if prompts:
            fh.write("\n".join(prompts) + "\n")
    arr = np.stack(grids) if grids else np.zeros((0, rows, cols), dtype=bool)
    with open(os.path.join(outdir, "inference.npz"), "wb") as fh:
        np.savez(fh, masks=arr)
    return masks


def rank_candidates(indir, cfg):
    close = cfg.get("close", {})
    target = float(close.get("target", 50.0))
    tol = float(close.get("tolerance", 25.0))
    path = os.path.join(indir, "candidates.json")
    if not os.path.exists(path):
        return []
    cands = json.load(open(path))
    kept = []
    for c in cands:
        metric = float(c["metric"])
        dist = abs(metric - target)
        if dist <= tol:  # inclusive tolerance
            kept.append({
                "id": str(c["id"]).strip(),
                "metric": float(metric),
                "target": float(target),
                "distance": round(dist, 4),
                "score": round(1.0 / (1.0 + dist), 6),
            })
    kept.sort(key=lambda r: (-r["score"], r["id"]))
    return kept


def run(indir, outdir):
    cfg = load_config(indir)
    move_docs(indir, outdir)
    masks = build_masks(indir, outdir, cfg)

    mart, unified = extract.build(indir, outdir)  # writes outdir/mart.npy

    order_rows = []
    for m in masks:
        inv = m["invoice_id"]
        amount, fee = unified.get(inv, (0.0, 0.0))
        order_rows.append((inv, float(amount), float(fee),
                           (float(amount) + float(fee)) * ITERATIONS))

    # --- close-out sheet at exact cell addresses ---
    lines = []
    for idx, (inv, amount, fee, prod) in enumerate(order_rows):
        k = idx + 1
        lines.append({"sheet": "GJ", "address": "A%d" % k, "value": amount, "invoice": inv})
        lines.append({"sheet": "GJ", "address": "B%d" % k, "value": fee, "invoice": inv})
        lines.append({"sheet": "GJ", "address": "C%d" % k, "value": prod, "invoice": inv})
    total = sum(r[3] for r in order_rows)
    lines.append({"sheet": "GJ", "address": "TOTAL", "value": float(total), "invoice": "*"})

    # --- fiscal cross-check over every mask row ---
    mis = []
    for m in masks:
        _, fee = unified.get(m["invoice_id"], (0.0, 0.0))
        if abs(float(fee) - m["expected_fee"]) > 1e-9:
            mis.append(m["invoice_id"])
    if mis:
        lines.append({"sheet": "GJ", "address": "NOTE",
                      "value": ",".join(mis), "invoice": "*"})
    else:
        lines.append({"sheet": "GJ", "address": "NOTE", "value": "OK", "invoice": "*"})

    with open(os.path.join(outdir, "sheet.jsonl"), "w") as fh:
        for ln in lines:
            fh.write(json.dumps(ln) + "\n")

    with open(os.path.join(outdir, "mismatch.txt"), "w") as fh:
        fh.write((",".join(mis) if mis else "NONE") + "\n")

    # --- filter/rank candidates by proximity ---
    with open(os.path.join(outdir, "ranked.json"), "w") as fh:
        json.dump(rank_candidates(indir, cfg), fh)

    print("RECONCILE OK invoices=%d mart=%s" % (len(masks), mart.shape))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default="/app")
    ap.add_argument("--output", default="/app")
    args = ap.parse_args()
    run(args.input, args.output)


if __name__ == "__main__":
    main()
