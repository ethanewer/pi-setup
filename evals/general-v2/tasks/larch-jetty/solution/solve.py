#!/usr/bin/env python3
"""Meridian back-office consolidator.

Reads a data directory and writes a full answer.json with:
  csv_rows        : every transaction row with every column's EXACT original
                    characters preserved (spelling / account-number variants,
                    amount sign and currency symbols included).
  top_categories  : up to five categories ranked by summed spend, descending;
                    ties broken alphabetically by category name.
  by_category     : category -> sorted, de-duplicated list of product ids.
  calendar_blocks : per .ics file the blocking (start,end) intervals parsed
                    from VEVENT blocks.
  availability    : for each candidate probe, whether the window is free
                    (no parsed block overlaps it).
  ip_dates        : for each line holding a valid IPv4, the LAST ISO date.
"""
import sys, os, re, json, csv, glob, argparse
from datetime import datetime

# --------------------------------------------------------------------------
# Documented contract helpers
# --------------------------------------------------------------------------

def amount_value(s):
    """Numeric value of a currency amount string. A leading '-' makes it
    negative; currency symbols and thousands separators are ignored; a string
    with no digits parses to 0.0 (train to: exact original string is what we
    keep in csv_rows).
    """
    s = s.strip()
    neg = s.startswith("-")
    digits = re.sub(r"[^0-9.]", "", s)
    v = float(digits) if digits else 0.0
    return -v if neg else v


def valid_ipv4(ip):
    """True only when ip is four dotted octets, no leading zeros, each 0-255."""
    parts = ip.split(".")
    if len(parts) != 4:
        return False
    for p in parts:
        if not p.isdigit():
            return False
        if len(p) > 1 and p.startswith("0"):
            return False
        if int(p) > 255:
            return False
    return True


IP_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
DATE_RE = re.compile(r"\b\d{4}-\d{2}-\d{2}\b")


def parse_ics(path):
    """Return [{summary, start, end}] for every VEVENT that has both a DTSTART
    and a DTEND; events lacking either are skipped."""
    events = []
    text = open(path, encoding="utf-8").read()
    for block in text.split("BEGIN:VEVENT")[1:]:
        rec = {"summary": "", "start": None, "end": None}
        for line in block.splitlines():
            if line.startswith("DTSTART"):
                rec["start"] = line.split(":", 1)[1].strip()
            elif line.startswith("DTEND"):
                rec["end"] = line.split(":", 1)[1].strip()
            elif line.startswith("SUMMARY"):
                rec["summary"] = line.split(":", 1)[1].strip()
        if rec["start"] and rec["end"]:
            events.append(rec)
    return events


def tok_to_dt(tok):
    # ICS timestamp token: YYYYMMDDTHHMMSSZ  (UTC)
    return datetime.strptime(tok.strip().rstrip("Z"), "%Y%m%dT%H%M%S")


def overlaps(a0, a1, b0, b1):
    """Half-open intervals: True when [a0,a1) and [b0,b1) share any moment."""
    return a0 < b1 and a1 > b0


# ---------------------------------------------------------------------------
# Consolidation
# ---------------------------------------------------------------------------

def consolidate(in_dir):
    # 1) transaction rows ----------------------------------------------------
    rows = []
    csv_path = os.path.join(in_dir, "transactions.csv")
    with open(csv_path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        header = reader.fieldnames
        for r in reader:
            if all((r.get(k) or "").strip() == "" for k in r):
                continue  # skip a fully blank data row
            rows.append({k: r[k] for k in header})

    totals = {}
    prods = {}
    for r in rows:
        cat = r["category"]
        totals[cat] = totals.get(cat, 0.0) + abs(amount_value(r["amount"]))
        prods.setdefault(cat, set()).add(r["product_id"])

    top = sorted(totals.keys(), key=lambda c: (-totals[c], c))[:5]
    by_category = {c: sorted(prods[c]) for c in sorted(prods)}

    # 2) calendar blocks
    cal_dir = os.path.join(in_dir, "calendars")
    blocks = {}
    for p in sorted(glob.glob(os.path.join(cal_dir, "*.ics"))):
        blocks[os.path.basename(p)] = parse_ics(p)

    # 3) availability probes
    availability = []
    cand_path = os.path.join(in_dir, "candidate.txt")
    if os.path.exists(cand_path):
        with open(cand_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                kv = {}
                for field in line.split(";"):
                    k, _, v = field.partition("=")
                    kv[k.strip()] = v.strip()
                fname = kv.get("file", "")
                s0, s1 = tok_to_dt(kv["start"]), tok_to_dt(kv["end"])
                free = True
                for ev in blocks.get(fname, []):
                    if overlaps(s0, s1, tok_to_dt(ev["start"]), tok_to_dt(ev["end"])):
                        free = False
                        break
                availability.append({
                    "file": fname,
                    "label": kv.get("label", ""),
                    "start": kv["start"],
                    "end": kv["end"],
                    "available": free,
                })

    # 4) last date on lines that carry a valid IPv4
    ip_dates = []
    with open(os.path.join(in_dir, "logbook.txt"), encoding="utf-8") as f:
        for line in f:
            hit = None
            for m in IP_RE.finditer(line):
                cand = m.group(0)
                if valid_ipv4(cand):
                    hit = cand
                    break
            if hit is None:
                continue
            dates = DATE_RE.findall(line)
            if dates:
                ip_dates.append({"ip": hit, "date": dates[-1]})

    return {
        "csv_rows": rows,
        "top_categories": top,
        "by_category": by_category,
        "calendar_blocks": blocks,
        "availability": availability,
        "ip_dates": ip_dates,
    }


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("input", nargs="?", default="/app/data")
    ap.add_argument("output", nargs="?", default="/app/answer.json")
    args = ap.parse_args(argv)
    result = consolidate(args.input)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    print("wrote", args.output)


if __name__ == "__main__":
    main(sys.argv[1:])