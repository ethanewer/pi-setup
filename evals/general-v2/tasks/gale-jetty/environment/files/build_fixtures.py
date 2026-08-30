#!/usr/bin/env python3
"""Gale-Jetty close-out fixtures (build-time materialization, run at image build).

Writes the working dataset the agent must consume into /app:
  inbox/                    mixed documents (INVOICE-headed files = invoice, else other)
  masks.csv                 per-row cell rectangles + expected fees (invoice order)
  hx/                       heterogeneous fiscal ledger (csv + json + parquet, one schema)
  candidates.json           candidate descriptors to filter/rank
  config.json               grid dims + close-out target/tolerance
  compute_seq.py            the sequential ITERATIONS constant (input, to import)

Nothing here is the answer; the extraction/ranking math lives in the agent's own
deliverable programs.
"""
import json
import os

PARENT = "/app"

INVOICES = [
    # id, (r0, c0, r1, c1), expected_fee, ledger_amount, ledger_fee
    ("401", (0, 0, 2, 1), 20.0, 500.0, 20.0),
    ("402", (1, 1, 3, 2), 30.0, 900.0, 30.0),
    ("403", (2, 0, 3, 3), 25.0, 700.0, 25.0),
    ("404", (1, 0, 4, 2), 124.0, 1500.0, 99.0),  # sole inconsistent figure
    ("405", (3, 3, 5, 4), 11.0, 300.0, 11.0),
]

INVOICE_DOCS = ["inv_alpha.txt", "inv_beta.txt", "inv_gamma.txt",
                "inv_delta.txt", "inv_omega.txt"]
OTHER_DOCS = ["memo_zeta.txt", "memo_theta.txt"]

CANDIDATES = [
    {"id": "C1", "metric": 45.0},
    {"id": "C2", "metric": 20.0},
    {"id": "C3", "metric": 75.0},
    {"id": "C4", "metric": 120.0},
    {"id": "C5", "metric": 50.0},
]

CONFIG = {
    "grid": {"rows": 8, "cols": 10},
    "close": {"target": 50.0, "tolerance": 25.0},
}


def main():
    # --- inbox documents ---
    inbox = os.path.join(PARENT, "inbox")
    os.makedirs(inbox, exist_ok=True)
    for fn in INVOICE_DOCS:
        with open(os.path.join(inbox, fn), "w") as f:
            f.write("INVOICE\nGale Jetty Logistics\ninvoice-%s\n" % fn)
    for fn in OTHER_DOCS:
        with open(os.path.join(inbox, fn), "w") as f:
            f.write("MEMO\ninteroffice note\n%s\n" % fn)

    # --- masks.csv (invoice order) ---
    with open(os.path.join(PARENT, "masks.csv"), "w") as f:
        f.write("invoice_id,row0,col0,row1,col1,expected_fee\n")
        for inv_id, rect, exp, _amt, _fee in INVOICES:
            r0, c0, r1, c1 = rect
            f.write("%s,%d,%d,%d,%d,%s\n" % (inv_id, r0, c0, r1, c1, exp))

    # --- heterogeneous ledger (same schema in all three formats) ---
    hx = os.path.join(PARENT, "hx")
    os.makedirs(hx, exist_ok=True)
    rows = [{"invoice_id": iid, "amount": amt, "fee": fe}
            for iid, _rect, _exp, amt, fe in INVOICES]

    import csv
    with open(os.path.join(hx, "ledger.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["invoice_id", "amount", "fee"])
        w.writeheader()
        w.writerows(rows)
    with open(os.path.join(hx, "ledger.json"), "w") as f:
        json.dump(rows, f)
    import pandas as pd
    pd.DataFrame(rows).to_parquet(os.path.join(hx, "ledger.parquet"), index=False)

    # --- candidates + config ---
    with open(os.path.join(PARENT, "candidates.json"), "w") as f:
        json.dump(CANDIDATES, f)
    with open(os.path.join(PARENT, "config.json"), "w") as f:
        json.dump(CONFIG, f)

    # --- sequential iteration constant (fixed input module) ---
    with open(os.path.join(PARENT, "compute_seq.py"), "w") as f:
        f.write("# Sequential iteration constant for the gale-jetty extraction.\n")
        f.write("ITERATIONS = 23\n")

    print("fixtures materialized into %s" % PARENT)


if __name__ == "__main__":
    main()
