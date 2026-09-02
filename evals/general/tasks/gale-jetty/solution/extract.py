#!/usr/bin/env python3
"""Gale-Jetty extraction engine (the runnable 'recover the matrix' script).

Reads the heterogeneous ledger under <input>/hx (csv/json/parquet), the invoice
order from <input>/masks.csv, and writes the recovered matrix to
<output>/mart.npy as a dense (N, 3) float array whose rows follow the masks.csv
invoice order: [amount, fee, (amount+fee)*ITERATIONS].

Runnable standalone:
    python3 /app/extract.py [--input /app] [--output /app]
"""
import argparse
import csv
import json
import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
# Reuse the sequential iteration count by import (never restate it inline).
from compute_parallel import ITERATIONS  # noqa: E402


def parse_ledger(hxdir):
    """Parse every present format (hx/*.csv, *.json, *.parquet) into one dict.

    Returns {invoice_id: (amount, fee)}. Missing formats are tolerated; a
    repeated id (last occurrence wins) keeps parsing robust.
    """
    unified = {}
    if not os.path.isdir(hxdir):
        return unified
    for fname in sorted(os.listdir(hxdir)):
        path = os.path.join(hxdir, fname)
        if not os.path.isfile(path):
            continue
        low = fname.lower()
        records = []
        try:
            if low.endswith(".csv"):
                df = pd.read_csv(path)
                for _, r in df.iterrows():
                    records.append((str(r["invoice_id"]), float(r["amount"]),
                                    float(r["fee"])))
            elif low.endswith(".json"):
                with open(path) as fh:
                    for obj in json.load(fh):
                        records.append((str(obj["invoice_id"]),
                                        float(obj["amount"]), float(obj["fee"])))
            elif low.endswith(".parquet"):
                df = pd.read_parquet(path)
                for _, r in df.iterrows():
                    records.append((str(r["invoice_id"]), float(r["amount"]),
                                    float(r["fee"])))
        except Exception:
            # A malformed file must never abort the whole pipeline.
            continue
        for inv, amount, fee in records:
            unified[inv] = (amount, fee)
    return unified


def invoice_order(homedir):
    """Invoice ids in masks.csv row order."""
    order = []
    path = os.path.join(homedir, "masks.csv")
    if os.path.exists(path):
        with open(path) as fh:
            for row in csv.DictReader(fh):
                order.append(str(row["invoice_id"]).strip())
    return order


def build(homedir, outdir):
    unified = parse_ledger(os.path.join(homedir, "hx"))
    mrows = []
    for inv in invoice_order(homedir):
        amount, fee = unified.get(inv, (0.0, 0.0))
        mrows.append([float(amount), float(fee),
                      (float(amount) + float(fee)) * ITERATIONS])
    mart = np.array(mrows, dtype=np.float64).reshape(-1, 3)
    os.makedirs(outdir, exist_ok=True)
    np.save(os.path.join(outdir, "mart.npy"), mart)
    return mart, unified


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default="/app")
    ap.add_argument("--output", default="/app")
    args = ap.parse_args()
    mart, _ = build(args.input, args.output)
    print("EXTRACT_OK", mart.shape)


if __name__ == "__main__":
    main()
