#!/usr/bin/env python3
"""Hidden case 'malformed': adversarial edges.

- One rectangle has out-of-order corners (row0>row1 and col0>col1); the solver
  must normalize to min/max and still produce the correct mask and mart.
- The heterogeneous ledger is parquet-only (neither csv nor json present).
- One candidate sits exactly on the inclusive tolerance boundary (distance 6
  with tolerance 6) and must be kept; another is far outside and dropped.
- One expected fee disagrees with the ledger fee -> a single mismatch id.
"""
import json
import os

INVOICES = [
    # id, (r0, c0, r1, c1), expected_fee, ledger_amount, ledger_fee
    ("1001", (3, 4, 1, 2), 8.0, 50.0, 3.0),   # reversed corners, mismatch (8 vs 3)
    ("1002", (0, 0, 1, 1), 4.0, 70.0, 4.0),
]
CANDIDATES = [
    {"id": "Y1", "metric": 56.0},
    {"id": "Y2", "metric": 60.0},
    {"id": "Y3", "metric": 48.0},
]
CONFIG = {"grid": {"rows": 8, "cols": 10}, "close": {"target": 50.0, "tolerance": 6.0}}


def build(root):
    os.makedirs(os.path.join(root, "inbox"), exist_ok=True)
    for iid, _r, _e, _a, _f in INVOICES:
        with open(os.path.join(root, "inbox", "rec_%s.txt" % iid), "w") as f:
            f.write("INVOICE\nrecord %s\n" % iid)
    with open(os.path.join(root, "inbox", "note_side.txt"), "w") as f:
        f.write("MEMO\nside note\n")

    with open(os.path.join(root, "masks.csv"), "w") as f:
        f.write("invoice_id,row0,col0,row1,col1,expected_fee\n")
        for iid, (r0, c0, r1, c1), exp, _a, _f in INVOICES:
            f.write("%s,%d,%d,%d,%d,%s\n" % (iid, r0, c0, r1, c1, exp))

    hx = os.path.join(root, "hx")
    os.makedirs(hx, exist_ok=True)
    import pandas as pd
    rows = [{"invoice_id": iid, "amount": a, "fee": f}
            for iid, _r, _e, a, f in INVOICES]
    pd.DataFrame(rows).to_parquet(os.path.join(hx, "ledger.parquet"), index=False)
    # deliberately only parquet here

    with open(os.path.join(root, "candidates.json"), "w") as f:
        json.dump(CANDIDATES, f)
    with open(os.path.join(root, "config.json"), "w") as f:
        json.dump(CONFIG, f)
