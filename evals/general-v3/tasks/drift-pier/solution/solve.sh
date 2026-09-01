#!/usr/bin/env bash
# Oracle for drift-pier: author the data-mart pipeline /app/clean.py, then run
# it on the shipped /app/data baseline to produce the /app deliverables
# (result.json, top.tsv) plus the filled tide table.
set -euo pipefail
cd /app

cat > /app/clean.py << 'PYEOF'
#!/usr/bin/env python3
"""Drift Pier data-mart close-out.

Reads a job input directory and recomputes every required output:

  python3 clean.py <input_dir> <output_dir>

Input files (in input_dir):
  ledger.json   - parties (id -> {name,balance}) and assets
                  ({id,name,owner,price}).
  transfers.csv - header: order,buyer,seller,asset ; proposed transfers.
  metrics.csv   - first column is the grouping key; remaining columns are
                  numeric or boolean.
  tide.csv      - port,hour,record ; empty record cells are interpolated.
  surge.tsv     - tab-separated request log with a column literally named url.
  schedule/*.ics - VEVENT slots become blocking intervals.

Outputs written to output_dir:
  result.json    - by_group, boolean_columns, balances, ownership,
                   transfer_log, slots.
  top.tsv        - url<TAB>count, frequency-ranked (top 3).
  tide_filled.csv - tide.csv with every record cell filled.
"""
import csv
import json
import os
import re
import sys

TRUE = {"1", "true", "yes", "t"}
FALSE = {"0", "false", "no", "f"}
TOP_K = 3


def parse_bool(v):
    s = str(v).strip().lower()
    if s in TRUE:
        return True
    if s in FALSE:
        return False
    return None


def load_rows(path, delimiter=","):
    with open(path, newline="") as fh:
        return list(csv.DictReader(fh, delimiter=delimiter))


def metric_job(inp):
    rows = load_rows(os.path.join(inp, "metrics.csv"))
    headers = list(rows[0].keys()) if rows else []
    group_key = headers[0] if headers else None

    def bool_col(vals):
        ne = [v for v in vals if str(v).strip() != ""]
        return bool(ne) and all(parse_bool(v) is not None for v in ne)

    boolean_cols = [h for h in headers[1:] if bool_col([r.get(h, "") for r in rows])]
    numeric_cols = [h for h in headers[1:] if h not in boolean_cols]

    groups = {}
    for r in rows:
        key = (r.get(group_key, "") or "").strip()
        if key == "":
            continue
        g = groups.setdefault(key, {"n": 0})
        g["n"] += 1
        for c in numeric_cols:
            try:
                v = float((r.get(c, "") or "").strip())
            except ValueError:
                v = None
            if v is not None:
                g[c + "_sum"] = g.get(c + "_sum", 0.0) + v
        for c in boolean_cols:
            if parse_bool(r.get(c, "")):
                g[c + "_true"] = g.get(c + "_true", 0) + 1
    for g in groups.values():
        for c in numeric_cols:
            if c + "_sum" in g:
                g[c + "_mean"] = round(g[c + "_sum"] / g["n"], 6)
                g[c + "_sum"] = round(g[c + "_sum"], 6)
        for c in boolean_cols:
            g.setdefault(c + "_true", 0)
    return {"boolean_columns": boolean_cols,
            "by_group": {k: groups[k] for k in sorted(groups)}}


def transfer_job(inp):
    ledger = json.load(open(os.path.join(inp, "ledger.json")))
    balances = {pid: float(p["balance"]) for pid, p in ledger["parties"].items()}
    assets = {a["id"]: ((a["owner"] or "").strip(), float(a["price"]))
              for a in ledger["assets"]}
    log = []
    for r in load_rows(os.path.join(inp, "transfers.csv")):
        order = (r["order"] or "").strip()
        buyer = (r["buyer"] or "").strip()
        seller = (r["seller"] or "").strip()
        asset = (r["asset"] or "").strip()
        reason = None
        if buyer not in balances or seller not in balances:
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
            balances[buyer] = round(balances[buyer] - price, 6)   # debit buyer
            balances[seller] = round(balances[seller] + price, 6)  # credit seller
            assets[asset] = (buyer, price)
            log.append({"order": order, "asset": asset, "buyer": buyer,
                        "seller": seller, "status": "approved", "price": price})
    return {"balances": {k: balances[k] for k in sorted(balances)},
            "ownership": {k: assets[k][0] for k in sorted(assets)},
            "transfer_log": log}


def interp_job(inp):
    rows = load_rows(os.path.join(inp, "tide.csv"))
    by_port = {}
    for i, r in enumerate(rows):
        by_port.setdefault((r["port"] or "").strip(), []).append((i, r))
    for p in by_port:
        by_port[p].sort(key=lambda t: (float(t[1]["hour"]), t[0]))
    filled = [None] * len(rows)
    for items in by_port.values():
        n = len(items)
        val = [None] * n
        for i in range(n):
            rec = (items[i][1]["record"] or "").strip()
            if rec:
                val[i] = float(rec)
        avail = [i for i in range(n) if val[i] is not None]
        if not avail:
            continue  # a port with no data stays empty
        for i in range(n):
            if val[i] is not None:
                filled[items[i][0]] = val[i]
                continue
            prev = [a for a in avail if a < i]
            nxt = [a for a in avail if a > i]
            if prev and nxt:
                pi, qi = prev[-1], nxt[0]
                hp = float(items[pi][1]["hour"])
                hq = float(items[qi][1]["hour"])
                hi = float(items[i][1]["hour"])
                frac = (hi - hp) / (hq - hp) if hq != hp else 0.0
                filled[items[i][0]] = val[pi] + (val[qi] - val[pi]) * frac
            elif prev:
                filled[items[i][0]] = val[prev[-1]]   # trailing clamp
            else:
                filled[items[i][0]] = val[nxt[0]]     # leading clamp
    out_rows = []
    for i, r in enumerate(rows):
        nr = dict(r)
        if filled[i] is not None:
            f = filled[i]
            nr["record"] = ("%.6f" % f) if (f % 1) else ("%d" % f)
        else:
            nr["record"] = ""
        out_rows.append(nr)
    return out_rows


def rank_job(inp):
    counts = {}
    for r in load_rows(os.path.join(inp, "surge.tsv"), delimiter="\t"):
        url = (r.get("url") or "").strip()
        if url:
            counts[url] = counts.get(url, 0) + 1
    return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[:TOP_K]


def ics_job(inp):
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


def main(inp, out):
    os.makedirs(out, exist_ok=True)
    res = {}
    res.update(metric_job(inp))
    res.update(transfer_job(inp))
    res.update({"slots": ics_job(inp)})
    with open(os.path.join(out, "result.json"), "w") as fh:
        json.dump(res, fh, indent=2)

    with open(os.path.join(out, "top.tsv"), "w") as fh:
        for url, cnt in rank_job(inp):
            fh.write("%s\t%d\n" % (url, cnt))

    out_rows = interp_job(inp)
    with open(os.path.join(out, "tide_filled.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=out_rows[0].keys())
        w.writeheader()
        w.writerows(out_rows)


if __name__ == "__main__":
    if len(sys.argv) >= 3:
        main(sys.argv[1], sys.argv[2])
    elif len(sys.argv) == 2:
        main(sys.argv[1], sys.argv[1])
    else:
        main("/app/data", "/app")
PYEOF

chmod +x /app/clean.py

# Run the pipeline on the shipped baseline to produce the deliverables at /app.
python3 /app/clean.py /app/data /app

echo "solution done: /app/clean.py /app/result.json /app/top.tsv /app/tide_filled.csv"
exit 0