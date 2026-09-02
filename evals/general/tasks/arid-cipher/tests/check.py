#!/usr/bin/env python3
"""Verifier helper. Independently recomputes the expected close-out artifacts
from a hidden input directory and compares them to what clean.py produced in
<out_dir>. Exit 0 iff everything matches. Exits non-zero on any failure."""
import os
import sys
import json
import numpy as np
import pandas as pd

BOOL_TRUE = {"1", "yes", "true", "t"}


def b(v):
    return str(v).strip().lower() in BOOL_TRUE


def fail(msg):
    print("CHECK FAIL:", msg)
    sys.exit(1)


def ok(msg):
    print("CHECK OK:", msg)


def check_hourly(inp, out):
    df = pd.read_csv(os.path.join(inp, "readings.csv"))
    df.columns = [c.strip() for c in df.columns]
    o = pd.read_csv(os.path.join(out, "hourly.csv"))
    o.columns = [c.strip() for c in o.columns]
    df["hour"] = pd.to_datetime(df["hour"])
    df["value"] = pd.to_numeric(df["value"], errors="coerce")
    df = df.sort_values("hour")
    ridx = pd.date_range(df["hour"].min().floor("h"), df["hour"].max().floor("h"), freq="h")
    ser = df.set_index("hour")["value"].reindex(ridx)
    exp = ser.interpolate(method="linear").ffill().bfill()
    got = o.set_index(pd.to_datetime(o["hour"]))["value"]
    # every expected hour present, no NaN, values match
    missing = [h for h in ridx if h not in got.index]
    if missing:
        fail(f"hourly missing hours: {missing[:5]}")
    if got.isna().any():
        fail("hourly contains NaN after fill")
    if len(got) != len(ridx):
        fail(f"hourly row count {len(got)} != {len(ridx)}")
    got = got[got.index.isin(ridx)].sort_index()
    if not np.allclose(got.values, exp.values, atol=1e-4):
        fail(f"hourly interpolation mismatch:\n got={got.values}\n exp={exp.values}")
    ok("hourly complete, boundary-filled, interpolated")


def check_metrics(inp, out):
    df = pd.read_csv(os.path.join(inp, "metrics.csv"))
    df.columns = [c.strip().lower() for c in df.columns]
    df["delivered"] = df["delivered"].map(b)
    df["critical"] = df["critical"].map(b)
    g = df.groupby(["region", "month"], as_index=False).agg(
        delivered_count=("delivered", "sum"),
        critical_count=("critical", "sum"),
        revenue_total=("revenue", "sum"),
        revenue_avg=("revenue", "mean"),
    )
    g["delivered_count"] = g["delivered_count"].astype(int)
    g["critical_count"] = g["critical_count"].astype(int)
    g["revenue_total"] = g["revenue_total"].round(2)
    g["revenue_avg"] = g["revenue_avg"].round(2)
    g = g.sort_values(["region", "month"]).reset_index(drop=True)
    o = pd.read_csv(os.path.join(out, "summaries.csv"))
    if list(o.columns) != list(g.columns):
        fail(f"summaries columns {list(o.columns)} != {list(g.columns)}")
    o = o.sort_values(["region", "month"]).reset_index(drop=True)
    if len(o) != len(g):
        fail(f"summaries row count {len(o)} != {len(g)}")
    if not np.allclose(o["revenue_total"].values, g["revenue_total"].values, atol=0.011):
        fail("summaries revenue_total mismatch")
    if not np.allclose(o["revenue_avg"].values, g["revenue_avg"].values, atol=0.011):
        fail("summaries revenue_avg mismatch")
    if not (o["delivered_count"].values == g["delivered_count"].values).all():
        fail("summaries delivered_count mismatch")
    if not (o["critical_count"].values == g["critical_count"].values).all():
        fail("summaries critical_count mismatch")
    ok("summaries aggregation (boolean detection) correct")

    cats = (
        df.groupby("region")["product_id"]
        .apply(lambda s: ";".join(sorted(set(s))))
        .reset_index()
    )
    cats.columns = ["category", "product_ids"]
    cats = cats.sort_values("category").reset_index(drop=True)
    o = pd.read_csv(os.path.join(out, "category_lists.csv"))
    if list(o.columns) != ["category", "product_ids"]:
        fail(f"category_lists columns {list(o.columns)}")
    o = o.sort_values("category").reset_index(drop=True)
    if not (o["category"].values == cats["category"].values).all():
        fail("category_lists category mismatch")
    if not (o["product_ids"].values == cats["product_ids"].values).all():
        fail("category_lists product_ids mismatch")
    ok("category_lists groupable by category")


def check_org(inp, out):
    df = pd.read_csv(os.path.join(inp, "org.csv"))
    df.columns = [c.strip().strip('"').strip() for c in df.columns]
    rows = df.dropna(subset=["dept", "employee", "project"])
    departments = {}
    for _, r in rows.iterrows():
        d, e, p = str(r["dept"]).strip(), str(r["employee"]).strip(), str(r["project"]).strip()
        departments.setdefault(d, {}).setdefault(e, set()).add(p)
    deps = []
    for d in sorted(departments):
        emps = [{"name": e, "projects": sorted(departments[d][e])} for e in sorted(departments[d])]
        deps.append({"name": d, "employees": emps})
    exp = {"departments": deps}
    with open(os.path.join(out, "result.json")) as fh:
        got = json.load(fh)
    if got != exp:
        fail(f"result.json mismatch:\n got={got}\n exp={exp}")
    # no duplicate projects within an employee
    for dep in got["departments"]:
        for emp in dep["employees"]:
            if len(emp["projects"]) != len(set(emp["projects"])):
                fail("result.json duplicate projects")
    ok("result.json nested graph sorted, deduped")


def check_target(inp, out):
    contacts = pd.read_csv(os.path.join(inp, "contacts.csv"))
    contacts.columns = [c.strip().strip('"').lower().strip() for c in contacts.columns]
    targets = pd.read_csv(os.path.join(inp, "targets.csv"), header=None).iloc[:, 0].dropna().astype(str).str.strip().str.lower()
    tokset = set(targets)

    def keep(row):
        return str(row["client"]).strip().lower() in tokset or str(row["account_id"]).strip().lower() in tokset

    exp = contacts[contacts.apply(keep, axis=1)].drop_duplicates().sort_values(["client", "account_id"]).reset_index(drop=True)
    o = pd.read_csv(os.path.join(out, "contacts_filtered.csv"))
    if list(o.columns) != list(exp.columns):
        fail(f"contacts_filtered columns {list(o.columns)} != {list(exp.columns)}")
    o = o.sort_values(["client", "account_id"]).reset_index(drop=True)
    if len(o) != len(exp):
        fail(f"contacts_filtered rows {len(o)} != {len(exp)}")
    if not (o["client"].values == exp["client"].values).all():
        fail("contacts_filtered client mismatch")
    if not (o["account_id"].values == exp["account_id"].values).all():
        fail("contacts_filtered account mismatch")
    ok("contacts_filtered target entity filtered")


def check_topk(inp, out):
    df = pd.read_csv(os.path.join(inp, "requests.csv"))
    df.columns = [c.strip().strip('"').lower() for c in df.columns]
    with open(os.path.join(inp, "topk.txt")) as fh:
        k = int(fh.read().strip())
    urls = df["url"].astype(str).str.strip()
    counts = urls.value_counts()
    ranked = counts.rename_axis("url").reset_index(name="count").sort_values(["count", "url"], ascending=[False, True])
    exp = ranked.head(k)
    rows = []
    with open(os.path.join(out, "top.tsv")) as fh:
        lines = [ln.rstrip("\n") for ln in fh if ln.strip()]
    if not lines or lines[0] != "url\tcount":
        fail("top.tsv missing header 'url\\tcount'")
    for ln in lines[1:]:
        parts = ln.split("\t")
        if len(parts) != 2:
            fail(f"top.tsv bad row: {ln!r}")
        rows.append((parts[0], int(parts[1])))
    if len(rows) != len(exp):
        fail(f"topk rows {len(rows)} != expected {len(exp)}")
    got = {(u, c) for u, c in rows}
    expset = {(r["url"], int(r["count"])) for _, r in exp.iterrows()}
    if got != expset:
        fail(f"topk content mismatch:\n got={got}\n exp={expset}")
    ok("top.tsv top-k counts correct")


def check_papers(inp, out):
    from html.parser import HTMLParser

    class P(HTMLParser):
        def __init__(self):
            super().__init__()
            self.papers = []
            self.cur = None
            self.in_id = False
            self.buf = []

        def handle_starttag(self, tag, attrs):
            a = dict(attrs)
            cls = a.get("class", "").split()
            if tag == "div" and "paper" in cls:
                self.cur = {"id": "", "url": ""}
            elif self.cur is not None and tag == "span" and "paper-id" in cls:
                self.in_id = True
                self.buf = []
            elif self.cur is not None and tag == "a" and "paper-link" in cls:
                self.cur["url"] = a.get("href", "").strip()
            elif self.cur is not None:
                self.buf = []

        def handle_data(self, d):
            if self.cur is not None and self.in_id:
                self.buf.append(d)

        def handle_endtag(self, tag):
            if self.in_id and tag == "span":
                self.cur["id"] = "".join(self.buf).strip()
                self.in_id = False
            elif self.cur is not None and tag == "div":
                self.papers.append(self.cur)
                self.cur = None

    parser = P()
    parser.feed(open(os.path.join(inp, "papers.html"), encoding="utf-8").read())
    n = len(parser.papers)
    lines = [ln for ln in open(os.path.join(out, "papers.jsonl"), encoding="utf-8") if ln.strip()]
    if len(lines) != n:
        fail(f"papers.jsonl records {len(lines)} != papers {n}")
    for ln in lines:
        try:
            obj = json.loads(ln)
        except Exception as e:
            fail(f"papers.jsonl unparseable: {ln!r} {e}")
        if sorted(obj.keys()) != ["id", "url"]:
            fail(f"papers.jsonl keys {sorted(obj.keys())} != ['id','url']")
        if not isinstance(obj["id"], str) or not isinstance(obj["url"], str):
            fail("papers.jsonl fields not strings")
    ok(f"papers.jsonl {n} records, exactly id+url")


def check_trials(inp, out):
    mat = np.loadtxt(os.path.join(inp, "recon/matrix.csv"), delimiter=",")
    with open(os.path.join(inp, "recon/rank.txt")) as fh:
        rank = int(fh.read().strip())
    td = os.path.join(out, "trials")
    names = sorted(os.listdir(td)) if os.path.isdir(td) else []
    exp_names = sorted("trial_%02d.csv" % i for i in range(20))
    if names != exp_names:
        fail(f"trials filenames {names} != expected {exp_names}")
    u, s, vt = np.linalg.svd(mat)
    k = max(1, min(rank, mat.shape[0]))
    low = np.dot(u[:, :k] * s[:k], vt[:k, :])
    for name in names:
        m = np.loadtxt(os.path.join(td, name), delimiter=",")
        su = np.linalg.svd(m, compute_uv=False)
        r = int(np.sum(su > 1e-7))
        if r != rank:
            fail(f"{name} rank {r} != {rank}")
        if not np.allclose(m, low, atol=1e-6):
            fail(f"{name} not equal to low-rank reconstruction")
    ok(f"trials: 20 low-rank CSVs (rank {rank})")


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: check.py <input_dir> <out_dir>")
    inp, out = sys.argv[1], sys.argv[2]
    for fn in ("summaries.csv", "category_lists.csv", "result.json",
               "contacts_filtered.csv", "top.tsv", "hourly.csv", "papers.jsonl"):
        if not os.path.exists(os.path.join(out, fn)):
            fail(f"missing output {fn}")
    check_hourly(inp, out)
    check_metrics(inp, out)
    check_org(inp, out)
    check_target(inp, out)
    check_topk(inp, out)
    check_papers(inp, out)
    check_trials(inp, out)
    print("CASE PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
