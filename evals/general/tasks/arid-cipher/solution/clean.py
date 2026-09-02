#!/usr/bin/env python3
"""ARID close-out pipeline.

Usage:
    python3 clean.py <input_dir> <output_dir>

Reads a data-mart input directory and emits the consolidated close-out
artifacts into <output_dir>. Exits 0 and prints a completion message on success.
"""
import os
import sys
import json
import numpy as np
import pandas as pd
from html.parser import HTMLParser

BOOL_TRUE = {"1", "yes", "true", "t", "true"}


def _b(v: str) -> bool:
    v = str(v).strip().lower()
    return v in BOOL_TRUE


def require(path):
    if not os.path.exists(path):
        raise RuntimeError("missing required input: " + path)
    return path


# --------------------------------------------------------------------------- #
# 1. metrics -> grouped aggregation summary + groupable-by-category table      #
# --------------------------------------------------------------------------- #
def build_metrics(inp, out):
    df = pd.read_csv(require(os.path.join(inp, "metrics.csv")))
    df.columns = [c.strip().lower() for c in df.columns]
    df["delivered"] = df["delivered"].map(_b)
    df["critical"] = df["critical"].map(_b)
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
    g.to_csv(os.path.join(out, "summaries.csv"), index=False)

    # groupable by category: per-category list of product ids
    cats = (
        df.groupby("region")["product_id"]
        .apply(lambda s: ";".join(sorted(set(s))))
        .reset_index()
    )
    cats.columns = ["category", "product_ids"]
    cats = cats.sort_values("category").reset_index(drop=True)
    cats.to_csv(os.path.join(out, "category_lists.csv"), index=False)


# --------------------------------------------------------------------------- #
# 2. org -> nested departments -> employees -> projects graph (result.json)    #
# --------------------------------------------------------------------------- #
def build_org(inp, out):
    df = pd.read_csv(require(os.path.join(inp, "org.csv")))
    df.columns = [c.strip().strip('"').strip() for c in df.columns]
    cols = [c.lower() for c in df.columns]
    if cols != ["dept", "employee", "project"]:
        # normalize if header came through differently
        raise RuntimeError("org.csv must have dept,employee,project columns")
    rows = df.dropna(subset=["dept", "employee", "project"])
    departments = {}
    for _, r in rows.iterrows():
        d = str(r["dept"]).strip()
        e = str(r["employee"]).strip()
        p = str(r["project"]).strip()
        emp = departments.setdefault(d, {})
        emp.setdefault(e, set()).add(p)
    deps = []
    for d in sorted(departments):
        emps = []
        for e in sorted(departments[d]):
            emps.append({"name": e, "projects": sorted(departments[d][e])})
        deps.append({"name": d, "employees": emps})
    result = {"departments": deps}
    with open(os.path.join(out, "result.json"), "w") as fh:
        json.dump(result, fh, indent=2, ensure_ascii=False)
        fh.write("\n")


# --------------------------------------------------------------------------- #
# 3. contacts filtered to a target entity across name/identifier variants      #
# --------------------------------------------------------------------------- #
def filter_target(inp, out):
    contacts = pd.read_csv(require(os.path.join(inp, "contacts.csv")))
    contacts.columns = [c.strip().strip('"').lower().strip() for c in contacts.columns]
    targets = pd.read_csv(
        require(os.path.join(inp, "targets.csv")), header=None
    ).iloc[:, 0].dropna().astype(str).str.strip().str.lower().tolist()
    tokset = set(targets)

    def keep(row):
        name = str(row["client"]).strip().lower()
        aid = str(row["account_id"]).strip().lower()
        return name in tokset or aid in tokset

    sel = contacts[contacts.apply(keep, axis=1)]
    sel = sel.drop_duplicates().sort_values(
        ["client", "account_id"]
    ).reset_index(drop=True)
    sel.to_csv(os.path.join(out, "contacts_filtered.csv"), index=False)


# --------------------------------------------------------------------------- #
# 4. rank request urls by frequency, write top-k with counts                  #
# --------------------------------------------------------------------------- #
def rank_urls(inp, out):
    df = pd.read_csv(require(os.path.join(inp, "requests.csv")))
    df.columns = [c.strip().strip('"').lower() for c in df.columns]
    kfile = os.path.join(inp, "topk.txt")
    with open(kfile) as fh:
        k = int(fh.read().strip())
    urls = df["url"].astype(str).str.strip()
    counts = urls.value_counts()
    ranked = counts.rename_axis("url").reset_index(name="count")
    ranked = ranked.sort_values(["count", "url"], ascending=[False, True])
    top = ranked.head(k)
    with open(os.path.join(out, "top.tsv"), "w") as fh:
        fh.write("url\tcount\n")
        for _, r in top.iterrows():
            fh.write(f"{r['url']}\t{int(r['count'])}\n")


# --------------------------------------------------------------------------- #
# 5. hourly series -> fill missing hours by linear interp + boundary fallback  #
# --------------------------------------------------------------------------- #
def build_hourly(inp, out):
    df = pd.read_csv(require(os.path.join(inp, "readings.csv")))
    df.columns = [c.strip().strip('"').lower() for c in df.columns]
    df["hour"] = pd.to_datetime(df["hour"])
    df["value"] = pd.to_numeric(df["value"], errors="coerce")
    df = df.sort_values("hour")
    ser = df.set_index("hour")["value"]
    ridx = pd.date_range(ser.index.min().floor("h"), ser.index.max().floor("h"), freq="h")
    ser = ser.reindex(ridx)
    filled = ser.interpolate(method="linear").ffill().bfill()
    outdf = pd.DataFrame({"hour": ridx.strftime("%Y-%m-%dT%H:%M:00"), "value": filled.round(6)})
    outdf.to_csv(os.path.join(out, "hourly.csv"), index=False)


PAPER_TRUE = BOOL_TRUE


class _Paper(HTMLParser):
    def __init__(self):
        super().__init__()
        self.papers = []
        self._cur = None
        self._in_id = False
        self._buf = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        classes = a.get("class", "").split()
        if tag == "div" and "paper" in classes:
            self._cur = {"id": "", "url": ""}
        elif self._cur is not None and tag == "span" and "paper-id" in classes:
            self._in_id = True
            self._buf = []
        elif self._cur is not None and tag == "a" and "paper-link" in classes:
            self._cur["url"] = a.get("href", "").strip()
        elif self._cur is not None:
            self._buf = []

    def handle_data(self, data):
        if self._cur is not None and self._in_id:
            self._buf.append(data)

    def handle_endtag(self, tag):
        if self._in_id and tag == "span":
            self._cur["id"] = "".join(self._buf).strip()
            self._in_id = False
        elif self._cur is not None and tag == "div":
            self.papers.append(self._cur)
            self._cur = None


# --------------------------------------------------------------------------- #
# 6. extract papers -> JSON Lines (id, url) per paper                          #
# --------------------------------------------------------------------------- #
def extract_papers(inp, out):
    with open(require(os.path.join(inp, "papers.html")), encoding="utf-8") as fh:
        html = fh.read()
    parser = _Paper()
    parser.feed(html)
    with open(os.path.join(out, "papers.jsonl"), "w", encoding="utf-8") as fh:
        for rec in parser.papers:
            fh.write(json.dumps({"id": rec.get("id", ""), "url": rec.get("url", "")}))
            fh.write("\n")


# --------------------------------------------------------------------------- #
# 7. repeat low-rank reconstruction across 20 trials -> trials/trial_*.csv     #
# --------------------------------------------------------------------------- #
def build_trials(inp, out):
    mat = pd.read_csv(require(os.path.join(inp, "recon/matrix.csv")), header=None).values.astype(float)
    with open(require(os.path.join(inp, "recon/rank.txt"))) as fh:
        rank = int(fh.read().strip())
    u, s, vt = np.linalg.svd(mat)
    k = max(1, min(rank, mat.shape[0]))
    low = np.dot(u[:, :k] * s[:k], vt[:k, :])
    os.makedirs(os.path.join(out, "trials"), exist_ok=True)
    for i in range(20):
        np.savetxt(os.path.join(out, "trials", "trial_%02d.csv" % i), low, delimiter=",")


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: clean.py <input_dir> <output_dir>")
    inp, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    build_hourly(inp, out)
    build_metrics(inp, out)
    build_org(inp, out)
    filter_target(inp, out)
    rank_urls(inp, out)
    extract_papers(inp, out)
    build_trials(inp, out)
    print("ARID-CLOSE-OUT COMPLETE: STATUS=OK")
    sys.exit(0)


if __name__ == "__main__":
    main()