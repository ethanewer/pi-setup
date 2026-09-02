#!/bin/bash
mkdir -p /logs/verifier
reward=0

if [ ! -f /app/reconcile.py ] || [ ! -s /app/reconcile.py ]; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

res=$(python3 - <<'EOF'
import json, os, re, math
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
    d = re.sub(r"[^0-9]", "", s)
    return d if d else None

cfg = json.load(open(CFG, encoding="utf-8"))

m = pd.read_csv(f"{SRC}/master_customers.csv", dtype=str)
m["customer_id"] = m["customer_id"].map(norm_id)
m["email"] = m["email"].map(norm_email)
m["phone"] = m["phone"].map(norm_phone)
for c in ["full_name", "region", "status", "created_at", "loyalty_tier"]:
    m[c] = m[c].map(norm)

o = pd.DataFrame(json.load(open(f"{SRC}/overrides.json", encoding="utf-8")))
for c in COLS:
    if c not in o.columns:
        o[c] = None
o["customer_id"] = o["customer_id"].map(norm_id)
o["email"] = o["email"].map(norm_email)
o["phone"] = o["phone"].map(norm_phone)
for c in ["full_name", "region", "status", "created_at", "loyalty_tier"]:
    o[c] = o[c].map(norm)

a = pd.read_parquet(f"{SRC}/attic_snapshot.parquet", columns=COLS)
a["customer_id"] = a["customer_id"].map(norm_id)
a["email"] = a["email"].map(norm_email)
a["phone"] = a["phone"].map(norm_phone)
for c in ["full_name", "region", "status", "created_at", "loyalty_tier"]:
    a[c] = a[c].map(norm)

byfile = {
    "master_customers.csv": m[COLS],
    "overrides.json": o[COLS],
    "attic_snapshot.parquet": a[COLS],
}
sources = [byfile[f] for f in sorted(cfg, key=lambda f: int(cfg[f]))]
all_ids = pd.Index(pd.concat([s["customer_id"] for s in sources], ignore_index=True).dropna().unique())
exp = pd.DataFrame(index=all_ids)
for col in COLS[1:]:
    acc = None
    for s in sources:
        sc = s.set_index("customer_id")[col].reindex(all_ids)
        if acc is None:
            acc = sc
        else:
            acc = acc.where(acc.notna(), sc)
    exp[col] = acc
exp = exp.reset_index().rename(columns={"index": "customer_id"})
exp = exp[COLS].sort_values("customer_id").reset_index(drop=True)
exp = exp.astype(object).where(pd.notna(exp), None)

if not os.path.exists(f"{OUT}/customers.parquet"):
    print("0"); raise SystemExit(0)
got = pd.read_parquet(f"{OUT}/customers.parquet")
if got.columns.tolist() != COLS:
    print("0"); raise SystemExit(0)
for c in COLS[1:]:
    got[c] = got[c].map(lambda v: None if (isinstance(v, str) and v.strip() == "") else v)
got["customer_id"] = got["customer_id"].map(norm_id)
got = got[COLS].sort_values("customer_id").reset_index(drop=True)

ok = True
if len(got) != len(exp):
    ok = False
if got["customer_id"].duplicated().any():
    ok = False
if got["customer_id"].isna().any():
    ok = False

def missing(v):
    return v is None or (isinstance(v, float) and math.isnan(v)) or v == ""

if ok:
    for _, erow in exp.iterrows():
        g = got[got["customer_id"] == erow["customer_id"]]
        if len(g) != 1:
            ok = False; break
        golden = g.iloc[0]
        for c in COLS[1:]:
            e, gg = erow[c], golden[c]
            if missing(e) and missing(gg):
                continue
            if e is None or gg is None:
                ok = False; break
            if str(e).strip().lower() != str(gg).strip().lower():
                ok = False; break
        if not ok:
            break

# manifest check
mfest = None
if os.path.exists(f"{OUT}/manifest.json"):
    try:
        mfest = json.load(open(f"{OUT}/manifest.json", encoding="utf-8"))
    except Exception:
        mfest = None
if mfest is None or mfest.get("row_count") != 30 or mfest.get("distinct_ids") != 30:
    ok = False

print("1" if ok else "0")
EOF
)

reward=${res:-0}
echo "$reward" > /logs/verifier/reward.txt