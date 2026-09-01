#!/usr/bin/env python3
"""Hidden case 'empty': tiny edge. Zero invoice rows in masks.csv (mart must be
shape (0, 3)), an empty heterogeneous ledger (header-only csv + empty json), a
single non-invoice inbox document, and a candidate exactly on the target
(distance 0) that must be ranked first.
"""
import json
import os

CANDIDATES = [
    {"id": "Z1", "metric": 10.0},
    {"id": "Z2", "metric": 12.0},
]
CONFIG = {"grid": {"rows": 8, "cols": 10}, "close": {"target": 10.0, "tolerance": 1.0}}


def build(root):
    os.makedirs(os.path.join(root, "inbox"), exist_ok=True)
    with open(os.path.join(root, "inbox", "memo_only.txt"), "w") as f:
        f.write("MEMO\nonly a memo\n")

    with open(os.path.join(root, "masks.csv"), "w") as f:
        f.write("invoice_id,row0,col0,row1,col1,expected_fee\n")

    hx = os.path.join(root, "hx")
    os.makedirs(hx, exist_ok=True)
    import csv
    with open(os.path.join(hx, "ledger.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["invoice_id", "amount", "fee"])
        w.writeheader()
    with open(os.path.join(hx, "ledger.json"), "w") as f:
        json.dump([], f)

    with open(os.path.join(root, "candidates.json"), "w") as f:
        json.dump(CANDIDATES, f)
    with open(os.path.join(root, "config.json"), "w") as f:
        json.dump(CONFIG, f)
