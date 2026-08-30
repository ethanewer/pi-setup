#!/usr/bin/env python3
"""Reference grader for the Meridian consolidator.

Re-computes the contract answer for an input directory from first principles
(the same documented rules solve.py must follow) and compares it field-by-field
with the answer JSON the deliverable produced. Exits 0 (prints OK) on a match,
otherwise prints FAIL ... and exits 1.

Usage: grader.py <input_dir> <answer.json>
"""
import sys, os, re, json, csv, glob
from datetime import datetime


def amount_value(s):
    s = s.strip()
    neg = s.startswith("-")
    digits = re.sub(r"[^0-9.]", "", s)
    v = float(digits) if digits else 0.0
    return -v if neg else v


def valid_ipv4(ip):
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
    return datetime.strptime(tok.strip().rstrip("Z"), "%Y%m%dT%H%M%S")


def overlaps(a0, a1, b0, b1):
    return a0 < b1 and a1 > b0


def expected(in_dir):
    rows = []
    with open(os.path.join(in_dir, "transactions.csv"), newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for r in reader:
            if all((r.get(k) or "").strip() == "" for k in r):
                continue
            rows.append({k: r[k] for k in reader.fieldnames})

    totals, prods = {}, {}
    for r in rows:
        cat = r["category"]
        totals[cat] = totals.get(cat, 0.0) + abs(amount_value(r["amount"]))
        prods.setdefault(cat, set()).add(r["product_id"])
    top = sorted(totals.keys(), key=lambda c: (-totals[c], c))[:5]
    by_category = {c: sorted(prods[c]) for c in sorted(prods)}

    blocks = {}
    for p in sorted(glob.glob(os.path.join(in_dir, "calendars", "*.ics"))):
        blocks[os.path.basename(p)] = parse_ics(p)

    availability = []
    cp = os.path.join(in_dir, "candidate.txt")
    if os.path.exists(cp):
        for line in open(cp, encoding="utf-8"):
            line = line.strip()
            if not line:
                continue
            kv = {}
            for field in line.split(";"):
                k, _, v = field.partition("=")
                kv[k.strip()] = v.strip()
            fn = kv.get("file", "")
            s0, s1 = tok_to_dt(kv["start"]), tok_to_dt(kv["end"])
            free = all(not overlaps(s0, s1, tok_to_dt(ev["start"]), tok_to_dt(ev["end"]))
                       for ev in blocks.get(fn, []))
            availability.append({
                "file": fn, "label": kv.get("label", ""),
                "start": kv["start"], "end": kv["end"], "available": free,
            })

    ip_dates = []
    for line in open(os.path.join(in_dir, "logbook.txt"), encoding="utf-8"):
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


def equal(a, b):
    return a == b


def compare(exp, act, path="root"):
    if type(exp) != type(act):
        return f"{path}: type mismatch {type(exp).__name__} vs {type(act).__name__}"
    if isinstance(exp, dict):
        if set(exp) != set(act):
            return f"{path}: keys differ missing={set(exp)-set(act)} extra={set(act)-set(exp)}"
        for k in exp:
            e = compare(exp[k], act[k], path + "." + k)
            if e:
                return e
        return None
    if isinstance(exp, list):
        if len(exp) != len(act):
            return f"{path}: length {len(exp)} vs {len(act)}"
        for i, (x, y) in enumerate(zip(exp, act)):
            e = compare(x, y, f"{path}[{i}]")
            if e:
                return e
        return None
    if exp != act:
        return f"{path}: {exp!r} != {act!r}"
    return None


def main(argv):
    if len(argv) < 2:
        print("usage: grader.py <input_dir> <answer.json>")
        return 2
    in_dir, ans_path = argv[0], argv[1]
    if not os.path.exists(ans_path):
        print("FAIL: answer file missing", ans_path)
        return 1
    act = json.load(open(ans_path, encoding="utf-8"))
    exp = expected(in_dir)
    err = compare(exp, act)
    if err:
        print("FAIL:", err)
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))