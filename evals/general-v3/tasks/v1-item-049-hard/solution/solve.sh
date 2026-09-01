#!/bin/bash
set -euo pipefail

cat > /app/reconcile.py <<'PYEOF'
#!/usr/bin/env python3
"""Config-driven customer reconciliation (item-049-hard)."""
import json, os, re
import pandas as pd

SRC = "/app/data/all_sources"
CFG = "/app/data/precedence.json"
OUT = "/app/output"
COLS = ["customer_id", "full_name", "email", "phone", "region", "status",
        "created_at", "loyalty_tier"]
SENTINELS = {"", "NULL", "N/A", "NA", "NAN"}


def norm(v):
    if v is None:
        return None
    s = str(v).strip()
    if s == "" or s.upper() in SENTINELS:
        return None
    return s


def norm_id(v):
    s = norm(v)
    return s.upper() if s else None


def norm_email(v):
    s = norm(v)
    return s.lower() if s else None


def norm_phone(v):
    s = norm(v)
    if s is None:
        return None
    digits = re.sub(r"[^0-9]", "", s)
    return digits if digits else None


def reconcile():
    cfg = json.load(open(CFG, encoding="utf-8"))

    m = pd.read_csv(f"{SRC}/master_customers.csv", dtype=str)
    m["customer_id"] = m["customer_id"].map(norm_id)
    m["email"] = m["email"].map(norm_email)
    m["phone"] = m["phone"].map(norm_phone)
    for col in ["full_name", "region", "status", "created_at", "loyalty_tier"]:
        m[col] = m[col].map(norm)

    o = pd.DataFrame(json.load(open(f"{SRC}/overrides.json", encoding="utf-8")))
    for col in COLS:
        if col not in o.columns:
            o[col] = None
    o["customer_id"] = o["customer_id"].map(norm_id)
    o["email"] = o["email"].map(norm_email)
    o["phone"] = o["phone"].map(norm_phone)
    for col in ["full_name", "region", "status", "created_at", "loyalty_tier"]:
        o[col] = o[col].map(norm)

    a = pd.read_parquet(f"{SRC}/attic_snapshot.parquet", columns=COLS)
    a["customer_id"] = a["customer_id"].map(norm_id)
    a["email"] = a["email"].map(norm_email)
    a["phone"] = a["phone"].map(norm_phone)
    for col in ["full_name", "region", "status", "created_at", "loyalty_tier"]:
        a[col] = a[col].map(norm)

    byfile = {
        "master_customers.csv": m[COLS],
        "overrides.json": o[COLS],
        "attic_snapshot.parquet": a[COLS],
    }
    # ascending rank => highest precedence first
    sources = [byfile[f] for f in sorted(cfg, key=lambda f: int(cfg[f]))]

    all_ids = pd.Index(pd.concat([s["customer_id"] for s in sources],
                                 ignore_index=True).dropna().unique())
    out = pd.DataFrame(index=all_ids)
    for col in COLS[1:]:
        acc = None
        for s in sources:
            sc = s.set_index("customer_id")[col].reindex(all_ids)
            acc = sc if acc is None else acc.where(acc.notna(), sc)
        out[col] = acc
    out = out.reset_index().rename(columns={"index": "customer_id"})
    out = out[COLS].sort_values("customer_id").reset_index(drop=True)
    out = out.astype(object).where(pd.notna(out), None)

    os.makedirs(OUT, exist_ok=True)
    out.to_parquet(f"{OUT}/customers.parquet", index=False)
    with open(f"{OUT}/manifest.json", "w", encoding="utf-8") as f:
        json.dump(
            {"row_count": len(out), "distinct_ids": int(out["customer_id"].nunique())},
            f,
        )
    return out


if __name__ == "__main__":
    r = reconcile()
    print(len(r))
PYEOF

python3 /app/reconcile.py