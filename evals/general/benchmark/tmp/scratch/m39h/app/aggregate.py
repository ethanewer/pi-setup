import os, csv, io, json
from datetime import datetime, timedelta

LOG = "/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m39h/app/logs"
CFG = "/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m39h/app/config.txt"
TOTALS = "/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m39h/app/totals.csv"

def parse_cfg():
    cfg = {}
    for line in open(CFG):
        line = line.strip()
        if '=' in line:
            k, v = line.split('=', 1)
            cfg[k.strip()] = v.strip()
    return cfg

cfg = parse_cfg()
tz = cfg['timezone']
start = datetime.fromisoformat(cfg['start']).date()
end = datetime.fromisoformat(cfg['end']).date()

def local_date(iso):
    dt = datetime.fromisoformat(iso.replace('Z', '+00:00'))
    off = timedelta(hours=-4) if tz == 'America/New_York' else timedelta(0)
    return (dt + off).date()

agg = {}
malformed = []
for fn in sorted(f for f in os.listdir(LOG) if f.startswith('sales_') and f.endswith('.csv')):
    rows = list(csv.reader(io.StringIO(open(os.path.join(LOG, fn), encoding='utf-8').read())))
    for idx, r in enumerate(rows[1:], start=2):
        reason = None
        a = None
        if len(r) != 5:
            reason = 'field_count'
        else:
            ts, store, region, amount, cur = [x.strip() for x in r]
            if cur != 'USD':
                reason = 'currency'
            elif not ts.endswith('Z'):
                reason = 'date'
            else:
                try:
                    a = float(amount)
                except Exception:
                    a = None
                if a is None:
                    reason = 'amount'
        if reason is not None:
            malformed.append(f"{fn}:{idx}:{reason}")
            continue
        ld = local_date(ts)
        if start <= ld < end:
            key = (ld.strftime('%Y-%m-%d'), region)
            old = agg.get(key, (0.0, 0))
            agg[key] = (old[0] + a, old[1] + 1)

# --- report.csv ---
rep = ["date,region,amount,row_count"]
for (d, region), (amt, cnt) in sorted(agg.items(), key=lambda kv: (kv[0][0], kv[0][1])):
    rep.append(f"{d},{region},{amt:.2f},{cnt}")
open("/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m39h/app/report.csv", "w").write("\n".join(rep) + "\n")

# --- reconciliation.csv ---
tot = {}
for line in open(TOTALS):
    line = line.strip()
    if line and not line.startswith('region'):
        r, e = line.split(',')
        tot[r.strip()] = float(e)
rec = ["region,expected_total,reported,difference,status"]
allok = True
for reg in sorted(tot):
    exp = tot[reg]
    repv = round(sum(v[0] for (d2, r2), v in agg.items() if r2 == reg), 2)
    delta = round(exp - repv, 2)
    st = 'match' if abs(delta) < 0.001 else 'mismatch'
    if st != 'match':
        allok = False
    rec.append(f"{reg},{exp:.2f},{repv:.2f},{delta:.2f},{st}")
open("/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m39h/app/reconciliation.csv", "w").write("\n".join(rec) + "\n")

meta = {"start": cfg['start'], "end": cfg['end'], "timezone": cfg['timezone'],
        "regions_aggregated": sorted({r for (_, r) in agg}),
        "total_rows": sum(v[1] for v in agg.values()),
        "reconciled": allok}
open("/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m39h/app/REPORT_META.json", "w").write(json.dumps(meta, indent=1))

open("/Users/ethanewer/pi-setup/evals/general/benchmark/tmp/scratch/m39h/app/malformed.log", "w").write("\n".join(malformed) + ("\n" if malformed else ""))
print("aggregation done")