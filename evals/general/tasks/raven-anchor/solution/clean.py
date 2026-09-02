#!/usr/bin/env python3
"""raven-anchor data-mart close-out pipeline.

CLI:  python3 clean.py <input_dir> <output_dir>

Reads the Raven data-mart inputs under <input_dir> and writes the eight
close-out artifacts into <output_dir>:

  aggregated.csv       grouped aggregation with boolean-column detection
  summary.csv          fixed-shape period,severity,count table
  result.json          nested departments -> employees -> projects graph
  projects_grouped.csv category/product-id groupable table
  filtered.csv         records of the target entity (across name variants)
  top.tsv              top-5 request URLs by frequency with counts
  series_filled.csv    hourly series with linear-interpolated gaps
  papers.jsonl         one two-field JSON line per paper

Exits 0 and prints a completion line on stdout when everything succeeded.
"""
import csv
import json
import os
import sys

BOOL_VOCAB = {"true", "false", "yes", "no", "1", "0", "y", "n", "t", "f"}
TRUTHY = {"true", "yes", "1", "y", "t"}
COMPLETE_LINE = "RAVEN-CLOSE-OUT COMPLETE: STATUS=OK"


def norm(v):
    return (v or "").strip()


def is_bool_word(v):
    return v.lower() in BOOL_VOCAB


def is_truthy(v):
    return norm(v).lower() in TRUTHY


def read_csv(path):
    """Return (header, rows) where header is lower-cased/stripped and each
    row is a dict keyed by that header, preserving original order."""
    if not os.path.exists(path):
        return [], []
    with open(path, "r", encoding="utf-8-sig", newline="") as f:
        raw = list(csv.reader(f))
    idx = 0
    while idx < len(raw) and not any((c or "").strip() for c in raw[idx]):
        idx += 1
    if idx >= len(raw):
        return [], []
    header = [(c or "").strip().lower() for c in raw[idx]]
    rows = []
    for rr in raw[idx + 1:]:
        if all((c or "").strip() == "" for c in rr):
            continue
        rows.append({h: (rr[i] if i < len(rr) else "") for i, h in enumerate(header)})
    return header, rows


def write_csv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        for r in rows:
            w.writerow([str(c) for c in r])


def fmt(v):
    return repr(round(float(v), 6))


def build_activity(data_dir, out_dir):
    header, rows = read_csv(os.path.join(data_dir, "activity.csv"))
    skip = {"period", "severity", "n_events"}
    bool_cols = [
        c for c in header
        if c not in skip
        and any((r.get(c) or "").strip() for r in rows)
        and all(is_bool_word((r.get(c) or "").strip()) for r in rows if (r.get(c) or "").strip())
    ]
    groups = {}
    order = []
    for r in rows:
        key = (norm(r.get("period")), norm(r.get("severity")))
        if key not in groups:
            groups[key] = [0, 0, [0] * len(bool_cols)]
            order.append(key)
        g = groups[key]
        g[0] += 1
        try:
            g[1] += int(norm(r.get("n_events")))
        except (TypeError, ValueError):
            pass
        for j, c in enumerate(bool_cols):
            if is_truthy(r.get(c)):
                g[2][j] += 1
    order.sort(key=lambda k: (k[0], k[1]))
    agg_rows = []
    sum_rows = []
    for period, severity in order:
        cnt, events, bcounts = groups[(period, severity)]
        agg_rows.append([period, severity, cnt, events] + bcounts)
        sum_rows.append([period, severity, cnt])
    write_csv(os.path.join(out_dir, "aggregated.csv"),
              ["period", "severity", "count", "events"]
              + [c + "_true" for c in bool_cols], agg_rows)
    write_csv(os.path.join(out_dir, "summary.csv"),
              ["period", "severity", "count"], sum_rows)


def build_graph(data_dir, out_dir):
    _, depts = read_csv(os.path.join(data_dir, "departments.csv"))
    _, emps = read_csv(os.path.join(data_dir, "employees.csv"))
    _, projs = read_csv(os.path.join(data_dir, "projects.csv"))
    tree = {}
    for d in depts:
        did = norm(d.get("dept_id"))
        if not did:
            continue
        tree[did] = {"dept_name": norm(d.get("dept_name")), "employees": {}}
    emp_dept = {}
    for e in emps:
        eid = norm(e.get("emp_id"))
        did = norm(e.get("dept_id"))
        if eid and did in tree:
            emp_dept[eid] = did
            tree[did]["employees"][eid] = {
                "emp_name": norm(e.get("emp_name")),
                "is_active": is_truthy(e.get("is_active")),
                "projects": {},
            }
    for p in projs:
        eid = norm(p.get("emp_id"))
        if eid not in emp_dept:
            continue
        tree[emp_dept[eid]]["employees"][eid]["projects"][norm(p.get("proj_id"))] = {
            "proj_title": norm(p.get("proj_title")),
            "category": norm(p.get("category")),
            "product_id": norm(p.get("product_id")),
        }
    with open(os.path.join(out_dir, "result.json"), "w") as f:
        json.dump(tree, f, indent=2, sort_keys=True)
        f.write("\n")


def build_projects_grouped(data_dir, out_dir):
    _, projs = read_csv(os.path.join(data_dir, "projects.csv"))
    groups = {}
    order = []
    for p in projs:
        key = (norm(p.get("category")), norm(p.get("product_id")))
        if key not in groups:
            groups[key] = 0
            order.append(key)
        groups[key] += 1
    order.sort(key=lambda k: (k[0], k[1]))
    write_csv(os.path.join(out_dir, "projects_grouped.csv"),
              ["category", "product_id", "count"],
              [[a, b, groups[(a, b)]] for a, b in order])


def build_filtered(data_dir, out_dir):
    _, aliases = read_csv(os.path.join(data_dir, "aliases.csv"))
    contact_header, contacts = read_csv(os.path.join(data_dir, "contacts.csv"))
    target = ""
    tp = os.path.join(data_dir, "target.txt")
    if os.path.exists(tp):
        with open(tp, encoding="utf-8") as f:
            target = f.read().strip()
    canonical = resolve_canonical(target, aliases, contacts)
    if canonical is None:
        keep = []
    else:
        keep = [c for c in contacts if norm(c.get("owner_id")) == canonical]
    keep.sort(key=lambda c: (norm(c.get("record_id")), norm(c.get("owner_id"))))
    write_csv(os.path.join(out_dir, "filtered.csv"),
              contact_header,
              [list(c.get(h, "") for h in contact_header) for c in keep])


def resolve_canonical(target, aliases, contacts):
    # search in bank
    for a in aliases:
        if norm(a.get("canonical_id")) == target:
            return norm(a.get("canonical_id"))
    for a in aliases:
        if norm(a.get("alias")) == target:
            return norm(a.get("canonical_id"))
    for c in contacts:
        if norm(c.get("owner_id")) == target:
            return norm(c.get("owner_id"))
    for c in contacts:
        if norm(c.get("owner_name")) == target:
            return norm(c.get("owner_id"))
    return None


def build_top(data_dir, out_dir, topn=5):
    _, reqs = read_csv(os.path.join(data_dir, "requests.csv"))
    counts = {}
    for r in reqs:
        u = norm(r.get("url"))
        if u == "":
            continue
        counts[u] = counts.get(u, 0) + 1
    items = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:topn]
    with open(os.path.join(out_dir, "top.tsv"), "w") as f:
        f.write("rank\turl\tcount\n")
        for i, (u, c) in enumerate(items, 1):
            f.write("%d\t%s\t%d\n" % (i, u, c))


def build_series(data_dir, out_dir):
    _, sr = read_csv(os.path.join(data_dir, "series.csv"))
    known = {}
    for r in sr:
        try:
            h = int(norm(r.get("hour")))
        except (TypeError, ValueError):
            continue
        vtxt = norm(r.get("value"))
        if vtxt == "":
            continue
        try:
            known[h] = float(vtxt)
        except ValueError:
            pass
    # span boundaries
    lo, hi = None, None
    sp = os.path.join(data_dir, "series_span.txt")
    if os.path.exists(sp):
        with open(sp, encoding="utf-8") as f:
            toks = f.read().split()
        if len(toks) >= 2:
            try:
                lo = int(toks[0])
                hi = int(toks[1])
            except ValueError:
                pass
    if lo is None or hi is None or hi < lo:
        lo, hi = 0, 0
        keep = []
    else:
        known_sorted = sorted(known)
        if not known_sorted:
            keep = []
        elif len(known_sorted) == 1:
            k = known_sorted[0]
            keep = [(h, known[k]) for h in range(lo, hi + 1)]
        else:
            keep = []
            for h in range(lo, hi + 1):
                if h in known:
                    keep.append((h, known[h]))
                    continue
                below = [x for x in known_sorted if x < h]
                above = [x for x in known_sorted if x > h]
                if below and above:
                    x0, x1 = below[-1], above[0]
                    y0, y1 = known[x0], known[x1]
                    keep.append((h, y0 + (y1 - y0) * (h - x0) / (x1 - x0)))
                elif below:
                    keep.append((h, known[below[-1]]))
                elif above:
                    keep.append((h, known[above[0]]))
                else:
                    keep.append((h, 0.0))
    write_csv(os.path.join(out_dir, "series_filled.csv"),
              ["hour", "value"], [[str(h), fmt(v)] for h, v in keep])


def build_papers(data_dir, out_dir):
    _, papers = read_csv(os.path.join(data_dir, "papers.csv"))
    with open(os.path.join(out_dir, "papers.jsonl"), "w") as f:
        for p in papers:
            obj = {"id": norm(p.get("paper_id")), "title": norm(p.get("title"))}
            f.write(json.dumps(obj) + "\n")


def main(argv):
    if len(argv) != 3:
        print("usage: clean.py <input_dir> <output_dir>", file=sys.stderr)
        return 2
    data_dir, out_dir = argv[1], argv[2]
    os.makedirs(out_dir, exist_ok=True)
    build_activity(data_dir, out_dir)
    build_graph(data_dir, out_dir)
    build_projects_grouped(data_dir, out_dir)
    build_filtered(data_dir, out_dir)
    build_top(data_dir, out_dir)
    build_series(data_dir, out_dir)
    build_papers(data_dir, out_dir)
    print(COMPLETE_LINE)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))