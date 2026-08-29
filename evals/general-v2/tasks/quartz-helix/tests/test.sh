#!/bin/bash
# Verifier for quartz-helix (data-mart close-out, executes-deliverable).
# (1) checks the delivered data artifacts /app/result.json and /app/top.tsv by
#     independently rebuilding the expected values from the shipped /app/data;
# (2) re-invokes the deliverable tool /app/clean.py on every hidden scenario and
#     compares each transform's output against an independent reference.
# Writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

[ -f /app/clean.py ] || { echo "missing /app/clean.py" >&2; echo "0" > /logs/verifier/reward.txt; exit 0; }
[ -f /app/result.json ] || { echo "missing /app/result.json" >&2; echo "0" > /logs/verifier/reward.txt; exit 0; }
[ -f /app/top.tsv ] || { echo "missing /app/top.tsv" >&2; echo "0" > /logs/verifier/reward.txt; exit 0; }

python3 - <<'PY'
import csv, json, math, os, shutil, subprocess, sys
from collections import OrderedDict, Counter
from datetime import datetime, date

FAILS = []
H = "/tests/hidden"

def run(*args):
    return subprocess.run(list(args), capture_output=True, text=True)

def read_csv(path, delim=","):
    with open(path, newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f, delimiter=delim)
        return [dict(r) for r in rd]

def num(v):
    if v is None: return None
    s = str(v).strip()
    if s == "": return None
    try: return float(s)
    except ValueError: return None

def close(a, b, tol=1e-6):
    if a is None and b is None: return True
    if a is None or b is None: return False
    return math.isclose(float(a), float(b), rel_tol=1e-6, abs_tol=tol)

def eq_rows(a_rows, b_rows):
    if len(a_rows) != len(b_rows): return False, "row count"
    for i, (ra, rb) in enumerate(zip(a_rows, b_rows)):
        if set(ra.keys()) != set(rb.keys()):
            return False, "row %d header" % i
        for k in ra:
            va, vb = ra[k], rb[k]
            if num(va) is not None and num(vb) is not None:
                if not close(va, vb): return False, "row %d col %s %r vs %r" % (i, k, va, vb)
            elif str(va).strip() != str(vb).strip():
                return False, "row %d col %s %r vs %r" % (i, k, va, vb)
    return True, ""

# ---------------------------------------------------------------- references
BOOL = {"0","1","yes","no","true","false","y","n","t","f"}
TRUE = {"1","yes","y","true","t"}

def ref_org(dept, emp, proj):
    org = {}
    for d in dept:
        did = (d.get("dept_id") or "").strip()
        if not did: continue
        org[did] = {"name": (d.get("dept_name") or "").strip(), "employees": [], "projects": []}
    for e in emp:
        did = (e.get("dept_id") or "").strip()
        nm = (e.get("emp_name") or "").strip()
        if did in org and nm: org[did]["employees"].append(nm)
    for p in proj:
        did = (p.get("dept_id") or "").strip()
        nm = (p.get("proj_name") or "").strip()
        if did in org and nm: org[did]["projects"].append(nm)
    body = {}
    for did in sorted(org):
        body[did] = {"name": org[did]["name"],
                     "employees": sorted(set(org[did]["employees"])),
                     "projects": sorted(set(org[did]["projects"]))}
    return {"organization": body}

def ref_topk(rows, k):
    cnt = Counter()
    for r in rows:
        u = (r.get("url") or "").strip()
        if u: cnt[u] += 1
    return sorted(cnt.items(), key=lambda kv: (-kv[1], kv[0]))[:k]

def ref_filter(rows, targets):
    names = {(t.get("display_name") or "").strip().lower() for t in targets if (t.get("display_name") or "").strip()}
    accs = {(t.get("account_id") or "").strip() for t in targets if (t.get("account_id") or "").strip()}
    out = []
    for r in rows:
        nm = (r.get("name") or "").strip().lower()
        ac = (r.get("account_id") or "").strip()
        if nm in names or ac in accs: out.append(r)
    return out

def ref_totals(rows):
    out = {}
    for r in rows:
        iid = (r.get("invoice_id") or "").strip()
        due, paid, tax = num(r.get("total_due")), num(r.get("paid")), num(r.get("tax_paid"))
        total = due if due is not None else paid
        conflict = due is not None and paid is not None and abs(due - paid) >= 0.005
        out[iid] = {"total_inclusive": total, "tax_amount": tax, "conflict": conflict}
    return {k: out[k] for k in sorted(out)}

def _ord(hs):
    t = datetime.strptime(hs, "%Y-%m-%d %H:%M")
    return t.date().toordinal() * 24 + t.hour

def _str(step):
    d = date.fromordinal(step // 24)
    return "%04d-%02d-%02d %02d:%02d" % (d.year, d.month, d.day, step % 24, 0)

def ref_series(rows):
    parsed = [( _ord(r["hour"]), num(r.get("value"))) for r in rows if (r.get("hour") or "").strip()]
    if not parsed: return []
    m = dict(parsed)
    full = list(range(min(m), max(m)+1))
    arr = [m.get(s) for s in full]
    known = [i for i,v in enumerate(arr) if v is not None]
    if known:
        first, last = known[0], known[-1]
        for i in range(first): arr[i] = arr[first]
        for i in range(last+1, len(arr)): arr[i] = arr[last]
        ks = [i for i,v in enumerate(arr) if v is not None]
        for a,b in zip(ks, ks[1:]):
            if b-a > 1:
                for j in range(a+1, b):
                    arr[j] = arr[a] + (arr[b]-arr[a]) * (j-a)/(b-a)
    return [( _str(s), arr[i]) for i,s in enumerate(full)]

def ref_grouped(rows, cat, vals):
    groups = OrderedDict()
    for r in rows:
        key = (r.get(cat) or "").strip()
        groups.setdefault(key, []).append(r)
    kinds, headers = {}, {}
    for v in vals:
        col = [r.get(v) for r in rows]
        ne = [c for c in col if (c or "").strip()]
        if ne and all((c or "").strip().lower() in BOOL for c in ne):
            kinds[v] = "bool"; headers[v] = v + "_true_frac"
        else:
            kinds[v] = "num"; headers[v] = v + "_mean"
    fields = [cat, "nrows"] + [headers[v] for v in vals]
    out = []
    for catv in sorted(groups):
        grp = groups[catv]
        row = OrderedDict([(cat, catv), ("nrows", len(grp))])
        for v in vals:
            col = [r.get(v) for r in grp]
            if kinds[v] == "bool":
                ne = [c for c in col if (c or "").strip()]
                t = sum(1 for c in ne if (c or "").strip().lower() in TRUE)
                row[headers[v]] = t / len(ne) if ne else None
            else:
                ns = [num(c) for c in col if num(c) is not None]
                row[headers[v]] = sum(ns)/len(ns) if ns else None
        out.append(row)
    return out, fields

def ref_papers(rows):
    return [{"title": (r.get("title") or "").strip(), "doi": (r.get("doi") or "").strip()} for r in rows]

# ---------------------------------------------------------------- checks
def check(name, cond, msg=""):
    if not cond:
        FAILS.append("%s: %s" % (name, msg))

# ---- visible deliverables rebuilt from /app/data ----
D = "/app/data"
dept = read_csv(D + "/departments.csv"); emp = read_csv(D + "/employees.csv"); proj = read_csv(D + "/projects.csv")
req = read_csv(D + "/requests.csv")
try:
    got = json.load(open("/app/result.json"))
except Exception as e:
    check("visible result.json", False, "unreadable: %s" % e); got = None
if got is not None:
    check("visible result.json", got == ref_org(dept, emp, proj), "org graph mismatch")
exp_top = ref_topk(req, 5)
try:
    got_top = [(ln.split("\t")[0], int(ln.split("\t")[1])) for ln in open("/app/top.tsv").read().splitlines() if ln.strip()]
except Exception as e:
    check("visible top.tsv", False, "unparseable: %s" % e); got_top = None
if got_top is not None:
    check("visible top.tsv", got_top == exp_top, "top-k mismatch: %r vs %r" % (got_top, exp_top))

# ---- hidden scenarios ----
# case1: organize
c1 = H + "/case1"
r = run("python3", "/app/clean.py", "organize", c1 + "/dept.csv", c1 + "/emp.csv", c1 + "/proj.csv", "-o", "/tmp/qh_org.json")
if r.returncode != 0:
    check("case1 organize", False, "crash: " + (r.stderr or r.stdout)[-200:])
else:
    try:
        g = json.load(open("/tmp/qh_org.json"))
        check("case1 organize", g == ref_org(read_csv(c1+"/dept.csv"), read_csv(c1+"/emp.csv"), read_csv(c1+"/proj.csv")), "org graph mismatch")
    except Exception as e:
        check("case1 organize", False, "output unreadable: %s" % e)

# case2: filter + topk
c2 = H + "/case2"
r = run("python3", "/app/clean.py", "filter", c2 + "/records.csv", c2 + "/target.csv", "-o", "/tmp/qh_f.csv")
if r.returncode != 0:
    check("case2 filter", False, "crash: " + (r.stderr or r.stdout)[-200:])
else:
    gotf = read_csv("/tmp/qh_f.csv")
    expf = ref_filter(read_csv(c2+"/records.csv"), read_csv(c2+"/target.csv"))
    ok, why = eq_rows(gotf, expf)
    check("case2 filter", ok, why)
    check("case2 filter count", len(gotf) == len(expf), "expected %d rows got %d" % (len(expf), len(gotf)))

r = run("python3", "/app/clean.py", "topk", c2 + "/requests.csv", "-k", "2", "-o", "/tmp/qh_top.tsv")
if r.returncode != 0:
    check("case2 topk", False, "crash: " + (r.stderr or r.stdout)[-200:])
else:
    got_t = [(ln.split("\t")[0], int(ln.split("\t")[1])) for ln in open("/tmp/qh_top.tsv").read().splitlines() if ln.strip()]
    exp_t = ref_topk(read_csv(c2+"/requests.csv"), 2)
    check("case2 topk", got_t == exp_t, "top-k mismatch %r vs %r" % (got_t, exp_t))

# case3: totals + series
c3 = H + "/case3"
r = run("python3", "/app/clean.py", "totals", c3 + "/invoices.tsv", "-o", "/tmp/qh_tot.json")
if r.returncode != 0:
    check("case3 totals", False, "crash: " + (r.stderr or r.stdout)[-200:])
else:
    try:
        g = json.load(open("/tmp/qh_tot.json"))
        e = ref_totals(read_csv(c3+"/invoices.tsv", "\t"))
        if set(g.keys()) != set(e.keys()):
            check("case3 totals", False, "invoice id set mismatch")
        else:
            bad = None
            for k in e:
                for fld in ("total_inclusive", "tax_amount", "conflict"):
                    ga, ea = g[k].get(fld), e[k].get(fld)
                    if isinstance(ga, bool) or isinstance(ea, bool):
                        if ga != ea: bad = (k, fld, ga, ea); break
                    elif not close(ga, ea): bad = (k, fld, ga, ea); break
                if bad: break
            check("case3 totals", bad is None, "mismatch %r" % (bad,))
    except Exception as ex:
        check("case3 totals", False, "unreadable: %s" % ex)

r = run("python3", "/app/clean.py", "series", c3 + "/hourly.tsv", "-o", "/tmp/qh_s.csv")
if r.returncode != 0:
    check("case3 series", False, "crash: " + (r.stderr or r.stdout)[-200:])
else:
    got_s = [(r["hour"], num(r["value"])) for r in read_csv("/tmp/qh_s.csv")]
    exp_s = ref_series(read_csv(c3+"/hourly.tsv", "\t"))
    if len(got_s) != len(exp_s):
        check("case3 series", False, "row count %d vs %d" % (len(got_s), len(exp_s)))
    else:
        bad = None
        for (gh, gv), (eh, ev) in zip(got_s, exp_s):
            if gh != eh or not close(gv, ev):
                bad = (gh, gv, eh, ev); break
        check("case3 series", bad is None, "series mismatch %r" % (bad,))

# case4: grouped + papers
c4 = H + "/case4"
r = run("python3", "/app/clean.py", "grouped", c4 + "/sales.csv", "--category", "category", "--vars", "revenue", "in_stock", "-o", "/tmp/qh_g.csv")
if r.returncode != 0:
    check("case4 grouped", False, "crash: " + (r.stderr or r.stdout)[-200:])
else:
    got_g = read_csv("/tmp/qh_g.csv")
    exp_g, fields = ref_grouped(read_csv(c4+"/sales.csv"), "category", ["revenue", "in_stock"])
    check("case4 grouped fields", [c for c in got_g[0].keys()] == fields if got_g else True, "field names")
    ok, why = eq_rows(got_g, exp_g)
    check("case4 grouped", ok, why)

r = run("python3", "/app/clean.py", "papers", c4 + "/papers.csv", "-o", "/tmp/qh_p.jsonl")
if r.returncode != 0:
    check("case4 papers", False, "crash: " + (r.stderr or r.stdout)[-200:])
else:
    lines = [ln for ln in open("/tmp/qh_p.jsonl").read().splitlines() if ln.strip()]
    exp_p = ref_papers(read_csv(c4+"/papers.csv"))
    if len(lines) != len(exp_p):
        check("case4 papers", False, "line count %d vs %d" % (len(lines), len(exp_p)))
    else:
        bad = None
        for ln, e in zip(lines, exp_p):
            try:
                o = json.loads(ln)
            except Exception as ex:
                bad = ("json", ex); break
            if set(o.keys()) != {"title", "doi"}:
                bad = ("fields", o); break
            if o["title"] != e["title"] or o["doi"] != e["doi"]:
                bad = ("value", o, e); break
        check("case4 papers", bad is None, "papers mismatch %r" % (bad,))

# ---- reward ----
if FAILS:
    print("FAILURES:")
    for m in FAILS:
        print("  - " + m)
    open("/logs/verifier/reward.txt", "w").write("0")
    sys.exit(0)

print("ALL PASS")
open("/logs/verifier/reward.txt", "w").write("1")
sys.exit(0)
PY
