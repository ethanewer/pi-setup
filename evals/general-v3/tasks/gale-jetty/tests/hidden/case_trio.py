#!/usr/bin/env python3
"""Hidden case 'trio': nominal differing data. 3 invoices, all fees consistent
(no mismatch), and the heterogeneous ledger is split across csv + json only
(no parquet present). Candidates: none trade below the tolerance floor on two
entries; two sit exactly equidistant (distance 5) so the tie must break by id.
"""
import json
import os

INVOICES = [
    # id, (r0, c0, r1, c1), expected_fee, ledger_amount, ledger_fee
    ("455", (0, 0, 1, 1), 12.0, 300.0, 12.0),
    ("456", (1, 0, 2, 2), 25.0, 620.0, 25.0),
    ("457", (0, 2, 1, 3), 17.0, 410.0, 17.0),
]
CANDIDATES = [
    {"id": "X1", "metric": 5.0},
    {"id": "X2", "metric": 12.0},
    {"id": "X3", "metric": 95.0},
    {"id": "X4", "metric": 105.0},
]
CONFIG = {"grid": {"rows": 8, "cols": 10}, "close": {"target": 100.0, "tolerance": 10.0}}


def build(root):
    os.makedirs(os.path.join(root, "inbox"), exist_ok=True)
    for iid, _r, _e, _a, _f in INVOICES:
        with open(os.path.join(root, "inbox", "inv_%s.txt" % iid), "w") as f:
            f.write("INVOICE\ninvoice %s\n" % iid)
    with open(os.path.join(root, "inbox", "memo_notes.txt"), "w") as f:
        f.write("MEMO\nstandalone note\n")

    with open(os.path.join(root, "masks.csv"), "w") as f:
        f.write("invoice_id,row0,col0,row1,col1,expected_fee\n")
        for iid, (r0, c0, r1, c1), exp, _a, _f in INVOICES:
            f.write("%s,%d,%d,%d,%d,%s\n" % (iid, r0, c0, r1, c1, exp))

    hx = os.path.join(root, "hx")
    os.makedirs(hx, exist_ok=True)
    import csv
    rows = [{"invoice_id": iid, "amount": a, "fee": f}
            for iid, _r, _e, a, f in INVOICES]
    with open(os.path.join(hx, "ledger.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["invoice_id", "amount", "fee"])
        w.writeheader()
        w.writerows(rows)
    with open(os.path.join(hx, "ledger.json"), "w") as f:
        json.dump(rows, f)
    # deliberately no parquet here

    with open(os.path.join(root, "candidates.json"), "w") as f:
        json.dump(CANDIDATES, f)
    with open(os.path.join(root, "config.json"), "w") as f:
        json.dump(CONFIG, f)
