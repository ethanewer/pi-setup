import csv, io, os, json
from datetime import datetime, timedelta

LOG="tmp/scratch/m39h/app/logs"; CFG="tmp/scratch/m39h/app/config.txt"; TOT="tmp/scratch/m39h/app/totals.csv"

def parse_cfg():
    cfg={}
    for line in open(CFG):
        line=line.strip()
        if '=' in line:
            k,v=line.split('=',1); cfg[k.strip()]=v.strip()
    return cfg

cfg=parse_cfg(); tz=cfg['timezone']
start=datetime.fromisoformat(cfg['start']).date()
end=datetime.fromisoformat(cfg['end']).date()

def local_date(iso):
    dt=datetime.fromisoformat(iso.replace('Z','+00:00'))
    off=timedelta(hours=-4) if tz=='America/New_York' else timedelta(0)
    return (dt+off).date()

agg={}; malform=[]
for fn in sorted(f for f in os.listdir(LOG) if f.startswith('sales_') and f.endswith('.csv')):
    rows=list(csv.reader(io.StringIO(open(os.path.join(LOG,fn),encoding='utf-8').read())))
    for idx,r in enumerate(rows[1:], start=2):
        reason=None
        a=None
        if len(r)!=5:
            reason='field_count'
        else:
            ts,store,region,amount,cur=[x.strip() for x in r]
            if cur!='USD':
                reason='currency'
            elif not ts.endswith('Z'):
                reason='date'
            else:
                try:
                    a=float(amount)
                except Exception:
                    a=None
                if a is None:
                    reason='amount'
        if reason is not None:
            malform.append(f"{fn}:{idx}:{reason}")
            continue
        ld=local_date(ts)
        if start<=ld<end:
            key=(ld.strftime('%Y-%m-%d'),region)
            old=agg.get(key,(0.0,0))
            agg[key]=(old[0]+a, old[1]+1)

tot={}
for line in open(TOT):
    line=line.strip()
    if line and not line.startswith('region'):
        r,e=line.split(','); tot[r.strip()]=float(e)

points=0

def read_csv(path):
    try:
        return open(path,encoding='utf-8').read().replace('\r\n','\n').strip().split('\n')
    except Exception:
        return None

# 1. report.csv exact
rep_exp=["date,region,amount,row_count"]
for (d,r),(amt,cnt) in sorted(agg.items(), key=lambda kv:(kv[0][0],kv[0][1])):
    rep_exp.append(f"{d},{r},{amt:.2f},{cnt}")
if read_csv("tmp/scratch/m39h/app/report.csv")==rep_exp:
    points=40
else:
    points=0

# 2. reconciliation.csv exact
rec_exp=["region,expected_total,reported,difference,status"]
allok=True
for reg in sorted(tot):
    exp=tot[reg]
    repv=round(sum(v[0] for (d2,r2),v in agg.items() if r2==reg),2)
    delta=round(exp-repv,2)
    st='match' if abs(delta)<0.001 else 'mismatch'
    if st!='match': allok=False
    rec_exp.append(f"{reg},{exp:.2f},{repv:.2f},{delta:.2f},{st}")
if read_csv("tmp/scratch/m39h/app/reconciliation.csv")==rec_exp:
    points += 35

# 3. REPORT_META.json
try:
    meta=json.load(open("tmp/scratch/m39h/app/REPORT_META.json"))
    exp_meta={"start":cfg['start'],"end":cfg['end'],"timezone":cfg['timezone'],
      "regions_aggregated":sorted({r for (_,r) in agg}),
      "total_rows":sum(v[1] for v in agg.values()),
      "reconciled": allok}
    if meta==exp_meta and meta.get("reconciled")==allok:
        points += 15
except Exception:
    pass

# 4. malformed.log exact (sorted lines)
try:
    got=open("tmp/scratch/m39h/app/malformed.log",encoding='utf-8').read().replace('\r\n','\n').strip()
    exp_mal="\n".join(sorted(malform))
    if got==exp_mal:
        points += 10
except Exception:
    pass

print(f"{min(points,100)/100.0:.2f}")