#!/usr/bin/env python3
"""
Manifest CLI for the "Cormorant Transit" data sweep.

Usage:
    python3 parse.py <indir> <outdir>

Reads, from <indir>:
    records.tsv          tabular records (multi-field, address uses '\\n' = line break)
    prefs/legacy.pkl     python pickle dict {guest_id: constraint}
    prefs/schedule.b64   base64-wrapped "guest_id:constraint" lines
    prefs/notes.txt      plain "guest_id:constraint" lines
    listing              a `tree -F` directory listing (box-drawing, markers)
    table.qdp            a QDP-style ascii table

Writes, to <outdir>:
    out.tsv    normalized per-record manifest
    tree.json  reconstructed nested directory tree
    qdp.tsv    parsed table rows
"""

import os
import re
import sys
import csv
import json
import base64
import pickle

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------

# lowercase null / masked value markers -> treated as absent data
MASKED = {"", "-", ".", "na", "n/a", "nan", "null", "none", "missing", "absent", "nil"}

MONTHS = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}

# QDP command keywords, recognised case-insensitively
QDP_COMMANDS = {"read", "skip", "res", "type", "decl", "num", "time", "bins"}

# tree -F trailing markers -> kind
TREE_MARKERS = {"/": "dir", "*": "exec", "@": "symlink", "|": "fifo", "=": "socket"}


# ----------------------------------------------------------------------------
# Field helpers
# ----------------------------------------------------------------------------

def norm_cell(s):
    """Strip whitespace; return None when the cell is a masked/empty marker."""
    if s is None:
        return None
    s = s.strip()
    if s.lower() in MASKED:
        return None
    return s


def parse_date(s):
    """Normalise a date string to YYYY-MM-DD; None when masked/unparsable."""
    s = norm_cell(s)
    if s is None:
        return None

    m = re.fullmatch(r"(\d{4})-(\d{1,2})-(\d{1,2})", s)
    if m:
        return "-".join(m.group(i) for i in (1, 2, 3))

    m = re.fullmatch(r"(\d{1,2})[/-](\d{1,2})[/-](\d{4})", s)
    if m:  # month/day/year (e.g. 05/20/2026)
        mm, dd, yyyy = m.groups()
        return f"{int(yyyy):04d}-{int(mm):02d}-{int(dd):02d}"

    m = re.fullmatch(r"(\d{4})[/-](\d{1,2})[/-](\d{1,2})", s)
    if m:  # year/month/day
        yyyy, mm, dd = m.groups()
        return f"{int(yyyy):04d}-{int(mm):02d}-{int(dd):02d}"

    m = re.fullmatch(r"(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})", s)
    if m:  # "3 Jun 2026"
        dd, mon, yyyy = m.groups()
        if mon.lower()[:3] in MONTHS:
            return f"{int(yyyy):04d}-{MONTHS[mon.lower()[:3]]:02d}-{int(dd):02d}"

    m = re.fullmatch(r"([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})", s)
    if m:  # "Jun 3, 2026"
        mon, dd, yyyy = m.groups()
        if mon.lower()[:3] in MONTHS:
            return f"{int(yyyy):04d}-{MONTHS[mon.lower()[:3]]:02d}-{int(dd):02d}"

    return None


def parse_lead(s):
    """Parse a numeric lead-days cell; None when masked/unparsable."""
    s = norm_cell(s)
    if s is None:
        return None
    m = re.fullmatch(r"(\d+)", s)
    if m:
        return int(m.group(1))
    return None


def parse_address(addr):
    """
    Address field encodes a street-number line break as the two-character
    sequence '\\n'. Layout:
        line1 : "<house number> <street>"
        line2 : "<city> <postal-code>"
    Returns (city, postal_code); empty strings when the break/postal is absent.
    """
    if addr is None:
        return "", ""
    lines = [ln.strip() for ln in str(addr).split("\\n")]
    lines = [ln for ln in lines if ln]
    if len(lines) < 2:
        return "", ""
    city_line = lines[1]
    toks = city_line.split()
    postal = ""
    rest = []
    for t in toks:
        if not postal and re.fullmatch(r"\d{5}", t):
            postal = t
        else:
            rest.append(t)
    city = " ".join(rest) if rest else ""
    return city, postal


# ----------------------------------------------------------------------------
# Preference fixtures (multiple encodings)
# ----------------------------------------------------------------------------

def load_prefs(prefdir):
    """Decode all preference/constraint fixture files -> {guest: (value, source)}."""
    prefs = {}

    # 1) python pickle dict
    p = os.path.join(prefdir, "legacy.pkl")
    if os.path.exists(p):
        with open(p, "rb") as fh:
            data = pickle.load(fh)
        for k, v in (data or {}).items():
            prefs[str(k)] = (str(v).strip(), "legacy.pkl")

    # 2) base64-wrapped key/value lines
    p = os.path.join(prefdir, "schedule.b64")
    if os.path.exists(p):
        raw = open(p, "rb").read().strip()
        try:
            text = base64.b64decode(raw).decode("utf-8", "replace")
        except Exception:
            text = ""
        for line in text.splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                k, v = k.strip(), v.strip()
                if k:
                    prefs[k] = (v, "schedule.b64")

    # 3) plain text key/value lines
    p = os.path.join(prefdir, "notes.txt")
    if os.path.exists(p):
        text = open(p, encoding="utf-8", errors="replace").read()
        for line in text.splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                k, v = k.strip(), v.strip()
                if k:
                    prefs[k] = (v, "notes.txt")

    return prefs


# ----------------------------------------------------------------------------
# tabular records -> manifest
# ----------------------------------------------------------------------------

def build_manifest(indir):
    prefs = load_prefs(os.path.join(indir, "prefs"))
    rpath = os.path.join(indir, "records.tsv")
    rows = []
    with open(rpath, encoding="utf-8", errors="replace", newline="") as fh:
        reader = csv.reader(fh, delimiter="\t")
        header = next(reader, None)
        if header is None:
            return "", rows
        try:
            gi = header.index("guest_id")
            ai = header.index("attendee")
            ad = header.index("address")
            dt = header.index("date")
            ld = header.index("lead_days")
        except ValueError:
            gi, ai, ad, dt, ld = 0, 1, 2, 3, 4
        for rec in reader:
            if not rec or not rec[gi].strip():
                continue
            gid = rec[gi].strip()
            attendee = rec[ai].strip() if len(rec) > ai else ""
            city, postal = parse_address(rec[ad] if len(rec) > ad else "")
            date_iso = parse_date(rec[dt] if len(rec) > dt else "")
            lead = parse_lead(rec[ld] if len(rec) > ld else "")
            if gid in prefs:
                pval, psrc = prefs[gid]
            else:
                pval, psrc = "absent", "absent"
            rows.append([
                gid, attendee, city or "", postal or "",
                date_iso or "", "" if lead is None else str(lead),
                pval, psrc,
            ])
    header_out = ["guest_id", "attendee", "city", "postal_code",
                  "date_iso", "lead_days", "preference", "source"]
    return header_out, rows


# ----------------------------------------------------------------------------
# tree -F listing -> nested JSON
# ----------------------------------------------------------------------------

def _tree_node(name):
    """Split a tree leaf name from its trailing -F marker."""
    name = name.strip()
    if name and name[-1] in TREE_MARKERS:
        return name[:-1].rstrip(), TREE_MARKERS[name[-1]]
    return name, "file"


def parse_tree(path):
    root = None
    levels = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            raw = raw.rstrip("\r\n")
            if not raw:
                continue
            # connector token
            idx = -1
            for conn in ("\u251c\u2500\u2500 ", "\u2514\u2500\u2500 "):
                pos = raw.find(conn)
                if pos != -1 and (idx == -1 or pos < idx):
                    idx = pos
            if idx == -1:
                # top-level root line (no indentation/connector)
                name, kind = _tree_node(raw)
                root = {"name": name, "kind": kind, "children": []}
                levels[1] = root
                continue
            prefix = raw[:idx]
            name, kind = _tree_node(raw[idx + 4:])
            depth = len(prefix) // 4 + 1
            node = {"name": name, "kind": kind}
            if kind == "dir":
                node["children"] = []
            parent = levels.get(depth - 1, root)
            parent.setdefault("children", []).append(node)
            levels[depth] = node
    return root


# ----------------------------------------------------------------------------
# QDP ascii table -> tsv rows
# ----------------------------------------------------------------------------

def parse_qdp(content):
    lines = content.splitlines()
    out = []
    i = 0
    total = len(lines)
    while i < total:
        line = lines[i].strip()
        if not line:
            i += 1
            continue
        if line.startswith("#"):
            i += 1
            continue
        toks = line.split()
        first = toks[0].lower()
        if first in QDP_COMMANDS:
            if first == "skip":
                # advance past the command line and ignore the next k lines
                k = int(toks[1]) if len(toks) > 1 and toks[1].isdigit() else 1
                i += 1 + k
            else:
                i += 1
            continue
        # otherwise a data row -> every token must be numeric
        try:
            vals = [float(t) for t in toks]
        except ValueError:
            # unrecognised non-numeric line: ignore it (robustness)
            i += 1
            continue
        out.append([f"{v:g}" for v in vals])
        i += 1
    return out


# ----------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------

def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: parse.py <indir> <outdir>\n")
        return 2
    indir, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)

    # 1) manifest
    header, rows = build_manifest(indir)
    with open(os.path.join(outdir, "out.tsv"), "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, delimiter="\t", lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)

    # 2) tree
    tree = parse_tree(os.path.join(indir, "listing"))
    with open(os.path.join(outdir, "tree.json"), "w", encoding="utf-8") as fh:
        json.dump(tree, fh, ensure_ascii=False)

    # 3) qdp
    qtext = open(os.path.join(indir, "table.qdp"), encoding="utf-8",
                 errors="replace").read()
    qrows = parse_qdp(qtext)
    with open(os.path.join(outdir, "qdp.tsv"), "w", encoding="utf-8", newline="") as fh:
        for row in qrows:
            fh.write("\t".join(row) + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
