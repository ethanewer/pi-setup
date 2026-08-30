#!/usr/bin/env python3
"""Independent verifier reference for raven-anchor.

Recomputes the expected close-out artifacts purely from the input_data dir and
compares them against /output_dir for every artifact the agent must produce.
Exits 0 only when every artifact matches exactly. This is the ground truth used
by tests/test.sh (itself independent of /app/clean.py's implementation style).
"""
import csv
import json
import os
import sys

BOOL_VOCAB = {"true", "false", "yes", "no", "1", "0", "y", "n", "t", "f"}
TRUTHY = {"true", "yes", "1", "y", "t"}

ARTIFACTS = [
    "aggregated.csv",
    "summary.csv",
    "result.json",
    "projects_grouped.csv",
    "top.tsv",
    "filtered.csv",
    "series_filled.csv",
    "papers.jsonl",
]


def norm(v):
    return (v or "").strip()


def is_bool_word(v):
    return v.lower() in BOOL_VOCAB


def is_truthy(v):
    return norm(v).lower() in TRUTHY


def read_csv_table(path):
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


def fmt(v):
    return repr(round(float(v), 6))


def norm_h(h):
    """Header names compared case-insensitively after trimming."""
    return (h or "").strip().lower()


def csv_rows_equal(a_rows, e_rows):
    """Structural/equivalence compare for CSV tables.

    Header names are compared case-insensitively after trimming; data cells
    are compared after trimming surrounding whitespace (whitespace around any
    cell is insignificant per the instruction, including in output artifacts).
    Row order and row count REMAIN significant, so sorting/grouping/filtering
    defects still fail. A fully-blank line is ignored, matching the
    'blank lines are insignificant' rule.
    """
    a = [r for r in a_rows if any((c or "").strip() for c in r)]
    e = [r for r in e_rows if any((c or "").strip() for c in r)]
    if len(a) != len(e):
        return False
    if not a:
        return True
    if [norm_h(c) for c in a[0]] != [norm_h(c) for c in e[0]]:
        return False
    for ar, er in zip(a[1:], e[1:]):
        if len(ar) != len(er):
            return False
        for ac, ec in zip(ar, er):
            if norm(ac) != norm(ec):
                return False
    return True


def series_rows_equal(a_rows, e_rows):
    """Compare series_filled.csv numerically: hours must be identical
    integers and values must both present the SAME numeric value rounded to 6
    decimal places (e.g. '10.0' and '10.000000' are equivalent). Row count
    and hour order remain significant."""
    a = [r for r in a_rows if any((c or "").strip() for c in r)]
    e = [r for r in e_rows if any((c or "").strip() for c in r)]
    if len(a) != len(e):
        return False
    if not a:
        return True
    if [norm_h(c) for c in a[0]] != [norm_h(c) for c in e[0]]:
        return False
    for ar, er in zip(a[1:], e[1:]):
        if len(ar) != 2 or len(er) != 2:
            return False
        try:
            ah, eh = int(norm(ar[0])), int(norm(er[0]))
            av, ev = float(norm(ar[1])), float(norm(er[1]))
        except (TypeError, ValueError):
            return False
        if ah != eh:
            return False
        if abs(av - ev) > 1e-6 * max(1.0, abs(ev), abs(av)):
            return False
    return True


def tsv_lines_equal(a_lines, e_lines):
    """top.tsv lines compared after trimming each tab-separated field."""
    def norm_line(ln):
        return "\t".join(norm(c) for c in ln.split("\t"))
    return [norm_line(x) for x in a_lines] == [norm_line(x) for x in e_lines]


def papers_equal(a_lines, e_lines):
    """papers.jsonl compared semantically: each line must be a JSON object
    with EXACTLY the two keys id/title, records in the same order, values
    equal after trimming (blank id/title kept as the empty string)."""
    if len(a_lines) != len(e_lines):
        return False
    for a, e in zip(a_lines, e_lines):
        try:
            ao, eo = json.loads(a), json.loads(e)
        except (TypeError, ValueError):
            return False
        if not isinstance(ao, dict) or not isinstance(eo, dict):
            return False
        if set(ao) != {"id", "title"}:
            return False
        if norm(ao.get("id")) != norm(eo.get("id")):
            return False
        if norm(ao.get("title")) != norm(eo.get("title")):
            return False
    return True


def ref_aggregated(d):
    header, rows = read_csv_table(os.path.join(d, "activity.csv"))
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
    agg = [["period", "severity", "count", "events"] + [c + "_true" for c in bool_cols]]
    for period, severity in order:
        cnt, events, bcounts = groups[(period, severity)]
        agg.append([period, severity, str(cnt), str(events)] + [str(x) for x in bcounts])
    summary = [["period", "severity", "count"]]
    for period, severity in order:
        summary.append([period, severity, str(groups[(period, severity)][0])])
    return agg, summary


def ref_graph(d):
    _, depts = read_csv_table(os.path.join(d, "departments.csv"))
    _, emps = read_csv_table(os.path.join(d, "employees.csv"))
    _, projs = read_csv_table(os.path.join(d, "projects.csv"))
    tree = {}
    for de in depts:
        did = norm(de.get("dept_id"))
        if not did:
            continue
        tree[did] = {"dept_name": norm(de.get("dept_name")), "employees": {}}
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
    return tree


def ref_projects_grouped(d):
    _, projs = read_csv_table(os.path.join(d, "projects.csv"))
    groups = {}
    order = []
    for p in projs:
        key = (norm(p.get("category")), norm(p.get("product_id")))
        if key not in groups:
            groups[key] = 0
            order.append(key)
        groups[key] += 1
    order.sort(key=lambda k: (k[0], k[1]))
    out = [["category", "product_id", "count"]]
    for a, b in order:
        out.append([a, b, str(groups[(a, b)])])
    return out


def ref_filtered(d):
    _, aliases = read_csv_table(os.path.join(d, "aliases.csv"))
    header, contacts = read_csv_table(os.path.join(d, "contacts.csv"))
    tp = os.path.join(d, "target.txt")
    target = ""
    if os.path.exists(tp):
        with open(tp, encoding="utf-8") as f:
            target = f.read().strip()
    canonical = None
    for a in aliases:
        if norm(a.get("canonical_id")) == target:
            canonical = norm(a.get("canonical_id"))
            break
    if canonical is None:
        for a in aliases:
            if norm(a.get("alias")) == target:
                canonical = norm(a.get("canonical_id"))
                break
    if canonical is None:
        for c in contacts:
            if norm(c.get("owner_id")) == target:
                canonical = norm(c.get("owner_id"))
                break
    if canonical is None:
        for c in contacts:
            if norm(c.get("owner_name")) == target:
                canonical = norm(c.get("owner_id"))
                break
    if canonical is None:
        keep = []
    else:
        keep = [c for c in contacts if norm(c.get("owner_id")) == canonical]
    # documented contract: rows sorted by record_id ascending (stable sort
    # keeps input order for ties); the instruction promises no secondary key
    keep.sort(key=lambda c: norm(c.get("record_id")))
    out = [header]
    for c in keep:
        out.append([c.get(h, "") for h in header])
    return out


def ref_top(d):
    _, reqs = read_csv_table(os.path.join(d, "requests.csv"))
    counts = {}
    for r in reqs:
        u = norm(r.get("url"))
        if u == "":
            continue
        counts[u] = counts.get(u, 0) + 1
    items = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:5]
    lines = ["rank\turl\tcount"]
    for i, (u, c) in enumerate(items, 1):
        lines.append("%d\t%s\t%d" % (i, u, c))
    return lines


def ref_series(d):
    _, sr = read_csv_table(os.path.join(d, "series.csv"))
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
    lo = hi = None
    sp = os.path.join(d, "series_span.txt")
    if os.path.exists(sp):
        with open(sp, encoding="utf-8") as f:
            toks = f.read().split()
        if len(toks) >= 2:
            try:
                lo, hi = int(toks[0]), int(toks[1])
            except ValueError:
                pass
    keep = []
    if lo is not None and hi is not None and hi >= lo:
        known_sorted = sorted(known)
        if len(known_sorted) == 1:
            k = known_sorted[0]
            keep = [(h, known[k]) for h in range(lo, hi + 1)]
        elif len(known_sorted) >= 2:
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
    out = [["hour", "value"]]
    for h, v in keep:
        out.append([str(h), fmt(v)])
    return out


def ref_papers(d):
    _, papers = read_csv_table(os.path.join(d, "papers.csv"))
    lines = []
    for p in papers:
        lines.append(json.dumps({"id": norm(p.get("paper_id")), "title": norm(p.get("title"))}))
    return lines


def read_csv_rows(path):
    with open(path, "r", newline="", encoding="utf-8") as f:
        return [list(r) for r in csv.reader(f)]


def main():
    if len(sys.argv) != 3:
        print("usage: check.py <input_dir> <output_dir>", file=sys.stderr)
        return 2
    data_dir, out_dir = sys.argv[1], sys.argv[2]
    agg, summary = ref_aggregated(data_dir)
    graph = ref_graph(data_dir)
    proj_grouped = ref_projects_grouped(data_dir)
    filtered = ref_filtered(data_dir)
    top = ref_top(data_dir)
    series = ref_series(data_dir)
    papers = ref_papers(data_dir)

    expected_csv = {
        "aggregated.csv": agg,
        "summary.csv": summary,
        "projects_grouped.csv": proj_grouped,
        "filtered.csv": filtered,
        "series_filled.csv": series,
    }
    ok = True
    for name, expected in expected_csv.items():
        p = os.path.join(out_dir, name)
        if not os.path.exists(p):
            print("MISSING %s" % name, file=sys.stderr)
            ok = False
            continue
        actual = read_csv_rows(p)
        if name == "series_filled.csv":
            same = series_rows_equal(actual, expected)
        else:
            same = csv_rows_equal(actual, expected)
        if not same:
            print("DIFF %s" % name, file=sys.stderr)
            print("  expected: %r" % expected, file=sys.stderr)
            print("  actual  : %r" % actual, file=sys.stderr)
            ok = False
    # result.json
    p = os.path.join(out_dir, "result.json")
    if not os.path.exists(p):
        print("MISSING result.json", file=sys.stderr)
        ok = False
    else:
        try:
            with open(p, encoding="utf-8") as f:
                got = json.load(f)
            # compare with sorted keys; the file is written sorted; compare semantic
            exp = json.loads(json.dumps(graph, sort_keys=True))
            if got != exp:
                print("DIFF result.json", file=sys.stderr)
                ok = False
        except Exception as e:
            print("result.json unparsable: %r" % e, file=sys.stderr)
            ok = False
    # top.tsv & papers.jsonl
    p = os.path.join(out_dir, "top.tsv")
    if not os.path.exists(p):
        print("MISSING top.tsv", file=sys.stderr)
        ok = False
    else:
        with open(p, encoding="utf-8") as f:
            got = f.read().splitlines()
        if not tsv_lines_equal(got, top):
            print("DIFF top.tsv", file=sys.stderr)
            ok = False
    p = os.path.join(out_dir, "papers.jsonl")
    if not os.path.exists(p):
        print("MISSING papers.jsonl", file=sys.stderr)
        ok = False
    else:
        with open(p, encoding="utf-8") as f:
            got = [ln for ln in f.read().splitlines() if ln.strip()]
        if not papers_equal(got, papers):
            print("DIFF papers.jsonl", file=sys.stderr)
            ok = False
    print("check.py: %s" % ("OK" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())