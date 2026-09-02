#!/usr/bin/env python3
"""Independent reference for the Drift Pier verifier.

Usage: check.py <input_dir> <output_dir>

Recomputes every required output from <input_dir> and compares it against the
files the pipeline wrote into <output_dir>. Exits 0 only if they all match.
Hand-written reference (not an import/re-run of /app/clean.py) so the task
cannot be satisfied by merely being the shipped sample.
"""
import csv
import json
import os
import re
import sys

inp, out = sys.argv[1], sys.argv[2]

TRUE = {"1", "true", "yes", "t"}
FALSE = {"0", "false", "no", "f"}


def parse_bool(v):
    s = str(v).strip().lower()
    if s in TRUE:
        return True
    if s in FALSE:
        return False
    return None


def near(a, b, tol=1e-6):
    return abs(a - b) <= tol


def rows_of(path, delimiter=","):
    with open(path, newline="") as fh:
        return list(csv.DictReader(fh, delimiter=delimiter))


failures = []


def checkpoint(name, ok, detail=""):
    if not ok:
        failures.append(name + ((" :: " + detail) if detail else ""))


# ---------------------------------------------------------------------------
# 1. metrics: boolean detection + grouped aggregation
# ---------------------------------------------------------------------------
def check_metrics():
    src = rows_of(os.path.join(inp, "metrics.csv"))
    headers = list(src[0].keys()) if src else []
    group_key = headers[0] if headers else None

    def boolcol(vals):
        ne = [v for v in vals if str(v).strip() != ""]
        return bool(ne) and all(parse_bool(v) is not None for v in ne)

    bool_cols = [h for h in headers[1:] if boolcol([r.get(h, "") for r in src])]
    num_cols = [h for h in headers[1:] if h not in bool_cols]

    groups = {}
    for r in src:
        key = (r.get(group_key, "") or "").strip()
        if not key:
            continue
        g = groups.setdefault(key, {"n": 0})
        g["n"] += 1
        for c in num_cols:
            try:
                v = float((r.get(c, "") or "").strip())
            except ValueError:
                v = None
            if v is not None:
                g[c + "_sum"] = g.get(c + "_sum", 0.0) + v
        for c in bool_cols:
            if parse_bool(r.get(c, "")):
                g[c + "_true"] = g.get(c + "_true", 0) + 1
    for g in groups.values():
        for c in num_cols:
            if c + "_sum" in g:
                g[c + "_mean"] = round(g[c + "_sum"] / g["n"], 6)
                g[c + "_sum"] = round(g[c + "_sum"], 6)
        for c in bool_cols:
            g.setdefault(c + "_true", 0)
    exp_groups = {k: groups[k] for k in sorted(groups)}

    res = json.load(open(os.path.join(out, "result.json")))
    checkpoint("result.json has boolean_columns", "boolean_columns" in res)
    checkpoint("result.json has by_group", "by_group" in res)
    checkpoint("boolean_columns match",
               sorted(res.get("boolean_columns", [])) == sorted(bool_cols))
    got_groups = res.get("by_group", {})
    checkpoint("by_group keys match", sorted(got_groups) == list(exp_groups))
    for key, eg in exp_groups.items():
        gg = got_groups.get(key, {})
        checkpoint(f"group {key} n", gg.get("n") == eg["n"])
        for c in num_cols:
            checkpoint(f"group {key} {c}_sum",
                       near(gg.get(c + "_sum"), eg[c + "_sum"], 1e-3))
            checkpoint(f"group {key} {c}_mean",
                       near(gg.get(c + "_mean"), eg[c + "_mean"], 1e-3))
        for c in bool_cols:
            checkpoint(f"group {key} {c}_true", gg.get(c + "_true") == eg[c + "_true"])


# ---------------------------------------------------------------------------
# 2. transfer rule
# ---------------------------------------------------------------------------
def read_transfers():
    ledger = json.load(open(os.path.join(inp, "ledger.json")))
    bal = {pid: float(p["balance"]) for pid, p in ledger["parties"].items()}
    assets = {a["id"]: ((a["owner"] or "").strip(), float(a["price"]))
              for a in ledger["assets"]}
    log = []
    for r in rows_of(os.path.join(inp, "transfers.csv")):
        order = (r["order"] or "").strip()
        buyer = (r["buyer"] or "").strip()
        seller = (r["seller"] or "").strip()
        asset = (r["asset"] or "").strip()
        reason = None
        if buyer not in bal or seller not in bal:
            reason = "unknown parties"
        elif buyer == seller:
            reason = "same party"
        elif asset not in assets:
            reason = "unknown asset"
        elif assets[asset][0] != seller:
            reason = "asset not owned by seller"
        if reason:
            log.append({"order": order, "asset": asset, "buyer": buyer,
                        "seller": seller, "status": "rejected",
                        "reason": reason, "price": None})
        else:
            price = assets[asset][1]
            bal[buyer] = bal[buyer] - price
            bal[seller] = bal[seller] + price
            assets[asset] = (buyer, price)
            log.append({"order": order, "asset": asset, "buyer": buyer,
                        "seller": seller, "status": "approved", "price": price})
    return ({k: bal[k] for k in sorted(bal)},
            {k: assets[k][0] for k in sorted(assets)},
            log)


def check_transfer():
    exp_bal, exp_own, exp_log = read_transfers()
    res = json.load(open(os.path.join(out, "result.json")))
    gbal = res.get("balances", {})
    gown = res.get("ownership", {})
    glog = res.get("transfer_log", [])
    checkpoint("balances keys", sorted(gbal) == sorted(exp_bal))
    for k, v in exp_bal.items():
        checkpoint(f"balance {k}", near(gbal.get(k, None), v, 1e-3))
    checkpoint("ownership keys", sorted(gown) == sorted(exp_own))
    for k, v in exp_own.items():
        checkpoint(f"owner {k}", gown.get(k) == v)
    checkpoint("transfer_log length", len(glog) == len(exp_log),
               f"{len(glog)} vs {len(exp_log)}")
    for i, (g, e) in enumerate(zip(glog, exp_log)):
        checkpoint(f"log[{i}].order", g.get("order") == e["order"])
        checkpoint(f"log[{i}].asset", g.get("asset") == e["asset"])
        checkpoint(f"log[{i}].buyer", g.get("buyer") == e["buyer"])
        checkpoint(f"log[{i}].seller", g.get("seller") == e["seller"])
        checkpoint(f"log[{i}].status", g.get("status") == e["status"])
        if e["status"] == "approved":
            gv = g.get("price")
            checkpoint(f"log[{i}].price",
                       isinstance(gv, (int, float)) and near(gv, e["price"], 1e-3))
        else:
            checkpoint(f"log[{i}].reason", g.get("reason") == e["reason"])
            checkpoint(f"log[{i}].price null", g.get("price") is None)


# ---------------------------------------------------------------------------
# 3. interpolation
# ---------------------------------------------------------------------------
def ref_interp():
    src = rows_of(os.path.join(inp, "tide.csv"))
    by_port = {}
    for i, r in enumerate(src):
        by_port.setdefault((r["port"] or "").strip(), []).append((i, r))
    for p in by_port:
        by_port[p].sort(key=lambda t: (float(t[1]["hour"]), t[0]))
    val = {}
    for items in by_port.values():
        vals = [None] * len(items)
        for i in range(len(items)):
            rec = (items[i][1]["record"] or "").strip()
            if rec:
                vals[i] = float(rec)
        avail = [i for i in range(len(items)) if vals[i] is not None]
        if not avail:
            for i in range(len(items)):
                val[items[i][0]] = None
            continue
        for i in range(len(items)):
            if vals[i] is not None:
                val[items[i][0]] = vals[i]
                continue
            prev = [a for a in avail if a < i]
            nxt = [a for a in avail if a > i]
            if prev and nxt:
                pi, qi = prev[-1], nxt[0]
                hp = float(items[pi][1]["hour"])
                hq = float(items[qi][1]["hour"])
                hi = float(items[i][1]["hour"])
                frac = (hi - hp) / (hq - hp) if hq != hp else 0.0
                val[items[i][0]] = vals[pi] + (vals[qi] - vals[pi]) * frac
            elif prev:
                val[items[i][0]] = vals[prev[-1]]
            else:
                val[items[i][0]] = vals[nxt[0]]
    return src, val


def check_interp():
    src, ref = ref_interp()
    got = rows_of(os.path.join(out, "tide_filled.csv"))
    checkpoint("tide_filled row count", len(got) == len(src))
    numeric_cells = 0
    empty_ports = 0
    if src:
        src_ports = {r["port"].strip() for r in src}
        port_data = {}
        for i, r in enumerate(src):
            port_data.setdefault(r["port"].strip(), 0)
            if (r["record"] or "").strip():
                port_data[r["port"].strip()] = 1
        empty_ports = sum(1 for p in port_data if port_data[p] == 0)
    for i, r in enumerate(src):
        exp_v = ref[i]
        gr = got[i] if i < len(got) else {}
        checkpoint(f"tide row {i} port", gr.get("port", "").strip() == r["port"].strip())
        try:
            gh = float((gr.get("hour") or "").strip())
        except (ValueError, TypeError):
            checkpoint(f"tide row {i} hour", False)
            continue
        checkpoint(f"tide row {i} hour",
                   abs(gh - float(r["hour"])) < 1e-9)
        if exp_v is None:
            checkpoint(f"tide row {i} empty", str(gr.get("record") or "").strip() == "")
        else:
            numeric_cells += 1
            try:
                gv = float((gr.get("record") or "").strip())
            except ValueError:
                checkpoint(f"tide row {i} numeric", False)
                continue
            checkpoint(f"tide row {i} value", near(gv, exp_v, 1e-3))
    checkpoint("tide numeric cells >0", numeric_cells > 0,
               "no port had any reading")
    checkpoint("empty ports preserved", empty_ports >= 0)


# ---------------------------------------------------------------------------
# 4. top-k urls
# ---------------------------------------------------------------------------
def check_top():
    counts = {}
    for r in rows_of(os.path.join(inp, "surge.tsv"), delimiter="\t"):
        url = (r.get("url") or "").strip()
        if url:
            counts[url] = counts.get(url, 0) + 1
    ranked = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:3]
    lines = [l for l in open(os.path.join(out, "top.tsv"), encoding="utf-8")
             if l.strip()]
    got = []
    for l in lines:
        url, cnt = l.rstrip("\n").split("\t")
        got.append((url, int(cnt)))
    checkpoint("top.tsv line count", len(got) == len(ranked),
               f"{len(got)} vs {len(ranked)}")
    for i, ((eu, ec), (gu, gc)) in enumerate(zip(ranked, got)):
        checkpoint(f"top[{i}] url", gu == eu)
        checkpoint(f"top[{i}] count", gc == ec)


# ---------------------------------------------------------------------------
# 5. iCal blocking intervals
# ---------------------------------------------------------------------------
def ref_ics():
    sched = os.path.join(inp, "schedule")
    ts_re = re.compile(r"^DTSTART:(\d{8}T\d{6})Z?$")
    te_re = re.compile(r"^DTEND:(\d{8}T\d{6})Z?$")

    def iso(tok):
        return "%s-%s-%sT%s:%s:%s" % (tok[0:4], tok[4:6], tok[6:8],
                                      tok[9:11], tok[11:13], tok[13:15])

    slots = {}
    if os.path.isdir(sched):
        for fname in sorted(os.listdir(sched)):
            if not fname.endswith(".ics"):
                continue
            pairs, start, seen = [], None, set()
            with open(os.path.join(sched, fname)) as fh:
                for line in fh:
                    line = line.strip()
                    m = ts_re.match(line)
                    if m:
                        start = iso(m.group(1))
                        continue
                    m = te_re.match(line)
                    if m and start is not None:
                        pair = (start, iso(m.group(1)))
                        if pair not in seen:
                            seen.add(pair)
                            pairs.append(list(pair))
                        start = None
            slots[fname] = pairs
    return slots


def check_ics():
    exp = ref_ics()
    res = json.load(open(os.path.join(out, "result.json")))
    got = res.get("slots", {})
    checkpoint("slots keys", sorted(got) == sorted(exp))
    for k, v in exp.items():
        checkpoint(f"slots[{k}] length", len(got.get(k, [])) == len(v))
        for i, pair in enumerate(v):
            g = got.get(k, [])
            checkpoint(f"slots[{k}][{i}]",
                       i < len(g) and len(g[i]) == 2
                       and g[i][0] == pair[0] and g[i][1] == pair[1])


check_metrics()
check_transfer()
check_interp()
check_top()
check_ics()

if failures:
    print("CHECK-FAIL %d:" % len(failures))
    for f in failures[:60]:
        print("  - " + f)
    sys.exit(1)
print("CHECK-OK")
sys.exit(0)