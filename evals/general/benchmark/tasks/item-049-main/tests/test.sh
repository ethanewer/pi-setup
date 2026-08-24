#!/bin/bash
mkdir -p /logs/verifier

reward=0
if [ ! -f /app/reconcile.py ] || [ ! -s /app/reconcile.py ]; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

res=$(python3 - <<'EOF'
import json, os, math
import pandas as pd

DATA = "/app/data/all_sources"
COLS = ["customer_id", "name", "email", "phone", "region", "status", "created_at"]

def missing(v):
    return v is None or (isinstance(v, float) and math.isnan(v)) or v == ""

# independent recomputation
master = pd.read_csv(f"{DATA}/master_customers.csv", dtype=str)
for c in COLS[1:]:
    if c in master.columns:
        master[c] = master[c].map(lambda v: None if (isinstance(v, str) and v.strip() == "") else v)
master["customer_id"] = master["customer_id"].str.strip().str.upper()

legacy = pd.DataFrame(json.load(open(f"{DATA}/legacy_customers.json", encoding="utf-8")))
legacy["customer_id"] = legacy["customer_id"].str.strip().str.upper()
for c in COLS[1:]:
    if c not in legacy.columns:
        legacy[c] = None
    else:
        legacy[c] = legacy[c].map(lambda v: None if (v is None or (isinstance(v, str) and v.strip() == "")) else v)

archive = pd.read_parquet(f"{DATA}/archive_snapshot.parquet", columns=COLS)
archive["customer_id"] = archive["customer_id"].str.strip().str.upper()

sources = [master[COLS], legacy[COLS], archive[COLS]]
all_ids = pd.Index(pd.concat([s["customer_id"] for s in sources], ignore_index=True).dropna().unique())
exp = pd.DataFrame(index=all_ids)
for col in COLS[1:]:
    outc = None
    for s in sources:
        s_col = s.set_index("customer_id")[col].reindex(all_ids)
        valid = s_col.notna()
        if outc is None:
            outc = s_col.astype(object).where(valid)
        else:
            outc = outc.where(outc.notna(), s_col.astype(object).where(valid))
    exp[col] = outc
exp = exp.reset_index().rename(columns={"index": "customer_id"})[COLS].sort_values("customer_id").reset_index(drop=True)

if not os.path.exists("/app/output/customers.parquet"):
    print("0"); raise SystemExit(0)
got = pd.read_parquet("/app/output/customers.parquet")
if got.columns.tolist() != COLS:
    print("0"); raise SystemExit(0)
for c in COLS[1:]:
    got[c] = got[c].map(lambda v: None if (isinstance(v, str) and v.strip() == "") else v)
got["customer_id"] = got["customer_id"].str.strip().str.upper()
got = got[COLS].sort_values("customer_id").reset_index(drop=True)

if len(got) != len(exp):
    print("0"); raise SystemExit(0)

ok = len(got) == len(exp)
for _, erows in exp.iterrows():
    g = got[got["customer_id"] == erows["customer_id"]]
    if len(g) != 1:
        ok = False; break
    golden = g.iloc[0]
    for c in COLS[1:]:
        e_, gg = erows[c], golden[c]
        if missing(e_) and missing(gg):
            continue
        if str(e_) != str(gg):
            ok = False; break
    if not ok:
        break

print("1" if ok else "0")
EOF
)

reward=${res:-0}
echo "$reward" > /logs/verifier/reward.txt