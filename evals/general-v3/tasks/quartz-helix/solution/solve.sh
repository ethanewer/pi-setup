#!/bin/bash
# Oracle for quartz-helix (data-mart close-out). Authors the real reusable
# tool /app/clean.py (all seven deterministic transforms), then RUNS it against
# the shipped workbench data to produce the two data deliverables:
#   /app/result.json  (nested org graph)
#   /app/top.tsv      (top-5 request URLs by frequency)
# Never reads /tests. Works from a pristine bench-base:python-3.12 container.
set -eu

cat > /app/clean.py <<'EOF'
#!/usr/bin/env python3
"""quartz-helix data-mart close-out tool.

Deterministic, self-contained transforms. Every subcommand reads one or more
CSV/TSV inputs and writes a precise output. Contracts (also what the verifier
re-checks on hidden inputs):

  organize  DEPT EMP PROJ  -> nested org JSON  (/app/result.json by default)
  filter    RECORDS TARGET -> entity-filtered records CSV
  topk      ACCESS -k N    -> "url<TAB>count" lines (desc freq, asc url tie)
  grouped   SALES --category C --vars V...          -> per-category aggregates CSV
  totals    INVOICES       -> per-invoice total & tax JSON
  series    HOURLY         -> hourly CSV with every step, gaps interpolated
  papers    PAPERS         -> JSON Lines, one line per paper with EXACTLY {title,doi}
"""
import sys, os, json, csv, argparse
from collections import OrderedDict, Counter
from datetime import datetime, date

TRUE = {"1", "yes", "y", "true", "t"}
BOOL = {"0", "1", "yes", "no", "true", "false", "y", "n", "t", "f"}


def read_rows(path, delim=None):
    with open(path, newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f, delimiter=delim or ",")
        fields = list(rd.fieldnames or [])
        return [dict(r) for r in rd], fields


def empt(v):
    return v is None or (isinstance(v, str) and v.strip() == "")


def clean(val):
    if empt(val):
        return ""
    return str(val).strip()


def to_num(val):
    if empt(val):
        return None
    try:
        return float(str(val).strip())
    except ValueError:
        return None


def detect_bool(values):
    """A value column is boolean-detected when it has at least one non-empty
    cell and every non-empty cell is a recognised boolean token."""
    ne = [c for c in values if not empt(c)]
    if not ne:
        return False
    return all(clean(c).lower() in BOOL for c in ne)


def frac_true(values):
    ne = [c for c in values if not empt(c)]
    if not ne:
        return None
    return sum(1 for c in ne if clean(c).lower() in TRUE) / len(ne)


def mean_num(values):
    ns = [to_num(c) for c in values if to_num(c) is not None]
    if not ns:
        return None
    return sum(ns) / len(ns)


def write_csv(path, rows, fields):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            out = {}
            for k in fields:
                v = r.get(k)
                out[k] = "" if v is None else v
            w.writerow(out)


def cmd_organize(a):
    dept, _ = read_rows(a.departments)
    emp, _ = read_rows(a.employees)
    proj, _ = read_rows(a.projects)
    org = OrderedDict()
    for d in dept:
        did = clean(d.get("dept_id"))
        if not did:
            continue
        org[did] = {"name": clean(d.get("dept_name")), "employees": [], "projects": []}
    for e in emp:
        did = clean(e.get("dept_id"))
        nm = clean(e.get("emp_name"))
        if did in org and nm:
            org[did]["employees"].append(nm)
    for p in proj:
        did = clean(p.get("dept_id"))
        nm = clean(p.get("proj_name"))
        if did in org and nm:
            org[did]["projects"].append(nm)
    body = {}
    for did in sorted(org):
        node = org[did]
        body[did] = {
            "name": node["name"],
            "employees": sorted(set(node["employees"])),
            "projects": sorted(set(node["projects"])),
        }
    with open(a.output, "w", encoding="utf-8") as f:
        json.dump({"organization": body}, f, indent=2, ensure_ascii=False)


def cmd_filter(args):
    rows, fields = read_rows(args.input, args.delim)
    tgt, _ = read_rows(args.target, args.delim)
    names = {clean(t.get("display_name")).lower() for t in tgt if clean(t.get("display_name"))}
    accs = {clean(t.get("account_id")) for t in tgt if clean(t.get("account_id"))}
    out = []
    for r in rows:
        nm = clean(r.get("name")).lower()
        ac = clean(r.get("account_id"))
        if nm in names or ac in accs:
            out.append(r)
    write_csv(args.output, out, fields)


def cmd_topk(args):
    rows, _ = read_rows(args.input, args.delim)
    cnt = Counter()
    for r in rows:
        u = clean(r.get("url"))
        if u:
            cnt[u] += 1
    order = sorted(cnt.items(), key=lambda kv: (-kv[1], kv[0]))[: args.k]
    with open(args.output, "w", encoding="utf-8") as f:
        for u, c in order:
            f.write("%s\t%d\n" % (u, c))


def cmd_totals(args):
    rows, _ = read_rows(args.input, args.delim)
    out = {}
    for r in rows:
        iid = clean(r.get("invoice_id"))
        due = to_num(r.get("total_due"))
        paid = to_num(r.get("paid"))
        tax = to_num(r.get("tax_paid"))
        total = due if due is not None else paid
        conflict = (
            due is not None and paid is not None and abs(due - paid) >= 0.005
        )
        out[iid] = {
            "total_inclusive": total,
            "tax_amount": tax,
            "conflict": conflict,
        }
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump({k: out[k] for k in sorted(out)}, f, indent=2)


def _hour_ordinal(hs):
    t = datetime.strptime(hs, "%Y-%m-%d %H:%M")
    return t.date().toordinal() * 24 + t.hour


def _hour_str(step):
    d = date.fromordinal(step // 24)
    hh = step % 24
    return "%04d-%02d-%02d %02d:%02d" % (d.year, d.month, d.day, hh, 0)


def cmd_series(args):
    rows, _ = read_rows(args.input, args.delim)
    parsed = []
    coln_hour = args.col_hour or "hour"
    coln_val = args.col_val or "value"
    for r in rows:
        hs = clean(r.get(coln_hour))
        if not hs:
            continue
        try:
            step = _hour_ordinal(hs)
        except ValueError:
            continue
        parsed.append((step, to_num(r.get(coln_val))))
    if not parsed:
        write_csv(args.output, [], ["hour", "value"])
        return
    m = {s: v for s, v in parsed}
    mi = min(m)
    ma = max(m)
    full = list(range(mi, ma + 1))
    arr = [m[s] for s in full]
    known_idx = [i for i, v in enumerate(arr) if v is not None]
    if known_idx:
        first, last = known_idx[0], known_idx[-1]
        for i in range(first):
            arr[i] = arr[first]
        for i in range(last + 1, len(arr)):
            arr[i] = arr[last]
        ks = [i for i, v in enumerate(arr) if v is not None]
        for a, b in zip(ks, ks[1:]):
            if b - a > 1:
                va, vb = arr[a], arr[b]
                for j in range(a + 1, b):
                    tfrac = (j - a) / (b - a)
                    arr[j] = va + (vb - va) * tfrac
    out = []
    for i, s in enumerate(full):
        out.append({"hour": _hour_str(s), "value": arr[i]})
    write_csv(args.output, out, ["hour", "value"])


def cmd_grouped(args):
    rows, _ = read_rows(args.input, args.delim)
    groups = OrderedDict()
    for r in rows:
        key = clean(r.get(args.category))
        groups.setdefault(key, []).append(r)
    kinds = {}
    headers = {}
    for v in args.vars:
        colvals = [r.get(v) for r in rows]
        if detect_bool(colvals):
            kinds[v] = "bool"
            headers[v] = "%s_true_frac" % v
        else:
            kinds[v] = "num"
            headers[v] = "%s_mean" % v
    fields = [args.category, "nrows"] + [headers[v] for v in args.vars]
    out = []
    for cat in sorted(groups):
        grp = groups[cat]
        row = {args.category: cat, "nrows": len(grp)}
        for v in args.vars:
            colvals = [r.get(v) for r in grp]
            if kinds[v] == "bool":
                row[headers[v]] = frac_true(colvals)
            else:
                row[headers[v]] = mean_num(colvals)
        out.append(row)
    write_csv(args.output, out, fields)


def cmd_papers(args):
    rows, _ = read_rows(args.input, args.delim)
    with open(args.output, "w", encoding="utf-8") as f:
        for r in rows:
            obj = {"title": clean(r.get("title")), "doi": clean(r.get("doi"))}
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def main():
    p = argparse.ArgumentParser(prog="clean")
    sub = p.add_subparsers(dest="cmd")

    o = sub.add_parser("organize")
    o.add_argument("departments")
    o.add_argument("employees")
    o.add_argument("projects")
    o.add_argument("-o", "--output", default="/app/result.json")

    f = sub.add_parser("filter")
    f.add_argument("input")
    f.add_argument("target")
    f.add_argument("-o", "--output")
    f.add_argument("--delim", default=",")

    t = sub.add_parser("topk")
    t.add_argument("input")
    t.add_argument("-o", "--output")
    t.add_argument("-k", type=int, default=5)
    t.add_argument("--delim", default=",")

    g = sub.add_parser("grouped")
    g.add_argument("input")
    g.add_argument("--category", required=True)
    g.add_argument("--vars", nargs="+", required=True)
    g.add_argument("-o", "--output")
    g.add_argument("--delim", default=",")

    tot = sub.add_parser("totals")
    tot.add_argument("input")
    tot.add_argument("-o", "--output")
    tot.add_argument("--delim", default="\t")

    s = sub.add_parser("series")
    s.add_argument("input")
    s.add_argument("-o", "--output")
    s.add_argument("--delim", default="\t")
    s.add_argument("--col-hour", default="hour")
    s.add_argument("--col-val", default="value")

    pa = sub.add_parser("papers")
    pa.add_argument("input")
    pa.add_argument("-o", "--output")
    pa.add_argument("--delim", default=",")

    a = p.parse_args()
    if a.cmd == "organize":
        cmd_organize(a)
    elif a.cmd == "filter":
        cmd_filter(a)
    elif a.cmd == "topk":
        cmd_topk(a)
    elif a.cmd == "grouped":
        cmd_grouped(a)
    elif a.cmd == "totals":
        cmd_totals(a)
    elif a.cmd == "series":
        cmd_series(a)
    elif a.cmd == "papers":
        cmd_papers(a)
    else:
        p.print_help()
        raise SystemExit(2)


if __name__ == "__main__":
    main()
EOF
chmod +x /app/clean.py
cd /app

# (1) nested org graph from the three shipped CSVs
python3 /app/clean.py organize /app/data/departments.csv /app/data/employees.csv /app/data/projects.csv -o /app/result.json
# (2) top-5 request URLs by frequency
python3 /app/clean.py topk /app/data/requests.csv -k 5 -o /app/top.tsv
