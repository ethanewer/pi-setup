#!/bin/bash
set -euo pipefail

cat > /app/reconcile.py <<'PYEOF'
#!/usr/bin/env python3
"""Reconcile three customer sources into one canonical parquet (item-049)."""
import json, os
import pandas as pd

DATA = "/app/data/all_sources"
COLS = ["customer_id", "name", "email", "phone", "region", "status", "created_at"]


def load_master():
    df = pd.read_csv(f"{DATA}/master_customers.csv", dtype=str)
    df = df.where(pd.notna(df) & (df != ""), None)
    df["customer_id"] = df["customer_id"].str.strip().str.upper()
    return df


def load_legacy():
    rows = json.load(open(f"{DATA}/legacy_customers.json", encoding="utf-8"))
    df = pd.DataFrame(rows, columns=COLS)
    df["customer_id"] = df["customer_id"].str.strip().str.upper()
    for c in COLS:
        if c in df.columns and df[c].dtype == object:
            df[c] = df[c].map(lambda v: None if (v is None or (isinstance(v, str) and v.strip() == "")) else v)
        elif c not in df.columns:
            df[c] = None
    return df[COLS]


def load_archive():
    df = pd.read_parquet(f"{DATA}/archive_snapshot.parquet", columns=COLS)
    df["customer_id"] = df["customer_id"].str.strip().str.upper()
    return df


def reconcile():
    master = load_master()
    legacy = load_legacy()
    archive = load_archive()
    sources = [master, legacy, archive]  # precedence high -> low

    all_ids = pd.Index(pd.concat([s["customer_id"] for s in sources], ignore_index=True).dropna().unique())
    out = pd.DataFrame(index=all_ids)
    for col in COLS[1:]:
        serie_cl = None
        for s in sources:
            s_col = s.set_index("customer_id")[col].reindex(all_ids)
            valid = s_col.notna()
            if serie_cl is None:
                serie_cl = s_col.where(valid)
            else:
                serie_cl = serie_cl.where(serie_cl.notna(), s_col.where(valid))
        out[col] = serie_cl
    out = out.reset_index().rename(columns={"index": "customer_id"})
    out = out[COLS].sort_values("customer_id").reset_index(drop=True)
    out = out.astype(object).where(pd.notna(out), None)
    os.makedirs("/app/output", exist_ok=True)
    out.to_parquet("/app/output/customers.parquet", index=False)
    return out


if __name__ == "__main__":
    result = reconcile()
    print(len(result))
PYEOF

python3 /app/reconcile.py