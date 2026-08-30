#!/usr/bin/env python3
"""dune-notch canonical parser.

Reads a directory of heterogeneous fixtures and emits a deterministic TSV of
rows ``<type>\t<key>\t<value>`` describing everything that could be derived.

Usage: python3 parse.py [IN_DIR [OUT_TSV]]
Defaults: IN_DIR=/app/data, OUT_TSV=/app/out.tsv
"""
import sys
import os
import json
import re
import datetime

try:
    import yaml
except Exception:  # pragma: no cover
    yaml = None

IN_DIR = "/app/data"
OUT_TSV = "/app/out.tsv"

# Case-insensitive sentinels that mean "absent data" in numeric cells.
MASKED = {"na", "n/a", "none", "null", "nan", "missing", "-", "--", "nil"}

MONTHS = {
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}


def fmt_num(v):
    """Canonical string for a numeric value (integral floats become ints)."""
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return repr(v)


def norm_date(s):
    """Normalize a date token to ISO YYYY-MM-DD (zero padded)."""
    s = s.strip()
    if s == "":
        return "--"
    y = mo = d = None
    # YYYY-M-D or YYYY-M-D with . separators
    m = re.fullmatch(r"(\d{4})[-.](\d{1,2})[-.](\d{1,2})", s)
    if m:
        y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
    else:
        m = re.fullmatch(r"(\d{1,2})/(\d{1,2})/(\d{4})", s)
        if m:
            mo, d, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
        else:
            m = re.fullmatch(r"(\d{1,2})[\s]+([A-Za-z]+)[\s]+(\d{4})", s)
            if m:
                d, mon, y = int(m.group(1)), m.group(2).lower(), int(m.group(3))
                mo = MONTHS.get(mon[:3])
                if mo is None:
                    return "INVALID"
            else:
                return "INVALID"
    try:
        dt = datetime.date(y, mo, d)
    except ValueError:
        return "INVALID"
    return dt.strftime("%Y-%m-%d")


def parse_people(path):
    """people.tsv -> per-person derived rows (person/team/born/avg)."""
    rows = []
    with open(path) as f:
        lines = [ln.rstrip("\n") for ln in f]
    # header line is first non-blank line
    start = 0
    while start < len(lines) and lines[start].strip() == "":
        start += 1
    if start >= len(lines):
        return rows
    header = [c.strip().lower() for c in lines[start].split("\t")]
    idx = {c: i for i, c in enumerate(header)}
    need = {"person_id", "first", "last", "initials", "institute",
            "birth_date", "am", "pm", "ev"}
    if not need.issubset(idx):
        return rows
    for ln in lines[start + 1:]:
        if ln.strip() == "":
            continue
        cells = ln.split("\t")
        if len(cells) != len(header):
            continue
        rec = {header[i]: cells[i] for i in range(len(header))}
        pid = rec["person_id"].strip()
        if pid == "":
            continue
        fullname = " ".join((rec["first"].strip(), rec["last"].strip()))
        # team name: INIT from initials tokens, INST from institute initials
        init_tokens = re.findall(r"[^\s]+", rec["initials"])
        init = "".join(t[0].upper() for t in init_tokens if t)
        inst_words = re.findall(r"[A-Za-z]+", rec["institute"])
        inst = "".join(w[0].upper() for w in inst_words if w)
        team = "T-%s-%s" % (init, inst)
        born = norm_date(rec["birth_date"])
        # numeric readings with masked markers -> absent
        vals = []
        for col in ("am", "pm", "ev"):
            tok = rec[col].strip()
            if tok.lower() in MASKED:
                continue
            try:
                vals.append(float(tok))
            except ValueError:
                continue
        if vals:
            avg = "%.2f" % (sum(vals) / len(vals))
        else:
            avg = "N/A"
        rows.append(("person", pid, fullname))
        rows.append(("team", pid, team))
        rows.append(("born", pid, born))
        rows.append(("avg", pid, avg))
    return rows


def parse_prefs(dirpath):
    """prefs.{json,ini,yaml} -> one pref row per person."""
    merged = {}

    def load_json():
        p = os.path.join(dirpath, "prefs.json")
        if not os.path.exists(p):
            return {}
        with open(p) as f:
            return {str(k): str(v) for k, v in json.load(f).items()}

    def load_ini():
        p = os.path.join(dirpath, "prefs.ini")
        if not os.path.exists(p):
            return {}
        out = {}
        cur = None
        with open(p) as f:
            for ln in f:
                s = ln.rstrip("\n").strip()
                if not s or s.startswith(("#", ";")):
                    continue
                if s.startswith("[") and s.endswith("]"):
                    cur = s[1:-1].strip()
                    continue
                if "=" in s:
                    k, v = s.split("=", 1)
                    out[k.strip()] = v.strip()
        return out

    def load_yaml():
        p = os.path.join(dirpath, "prefs.yaml")
        if not os.path.exists(p):
            return {}
        if yaml is None:
            # minimal fallback: "key: value" lines
            out = {}
            with open(p) as f:
                for ln in f:
                    s = ln.rstrip("\n").strip()
                    if not s or s.startswith("#"):
                        continue
                    if ":" in s:
                        k, v = s.split(":", 1)
                        out[k.strip()] = str(v).strip()
            return out
        with open(p) as f:
            data = yaml.safe_load(f) or {}
        if not isinstance(data, dict):
            return {}
        return {str(k): str(v) for k, v in data.items()}

    for fn in (load_json, load_ini, load_yaml):
        merged.update(fn())

    rows = []
    for pid in sorted(merged):
        rows.append(("pref", pid, merged[pid]))
    return rows


def parse_addresses(path):
    """addresses.txt blocks (street/number/city) -> city rows."""
    rows = []
    with open(path) as f:
        raw = f.read()
    blocks = re.split(r"\n\s*\n", raw)
    n = 0
    for blk in blocks:
        lines = [ln.strip() for ln in blk.strip("\n").split("\n")]
        lines = [ln for ln in lines if ln != ""]
        if len(lines) != 3:
            continue
        if not lines[1][0].isdigit():
            continue
        n += 1
        rows.append(("city", "addr-%d" % n, lines[2]))
    return rows


_KIND = {"/": "dir", "*": "exec", "@": "symlink", "|": "fifo", "=": "socket"}


def parse_tree(path):
    """dirlist.txt (tree -F listing) -> nested paths with kind."""
    rows = []
    with open(path) as f:
        lines = [ln.rstrip("\n") for ln in f]
    stack = []  # (level, path_parts) for open dirs
    for ln in lines:
        if ln.strip() == "":
            continue
        lead = len(ln) - len(ln.lstrip(" "))
        content = ln.strip()
        level = lead // 2
        last = content[-1]
        kind = _KIND.get(last, "file")
        name = content[:-1] if last in _KIND else content
        while stack and stack[-1][0] >= level:
            stack.pop()
        base = stack[-1][1] if stack else []
        fullpath = base + [name]
        fp = "/".join(fullpath)
        rows.append(("tree", fp, kind))
        if kind == "dir":
            stack.append((level, fullpath))
    return rows


_QDP_CMDS = {"read", "serr", "line", "point", "timesave", "norm", "color",
             "view", "device", "timedata", "header", "command", "plot",
             "noco", "time", "exit"}


def parse_qdp(path):
    """table.qdp (lowercase command/header) -> per-column sums."""
    labels = {}
    data = []
    with open(path) as f:
        for ln in f:
            s = ln.strip()
            if not s:
                continue
            toks = s.split()
            first = toks[0].lower()
            if first == "name":
                if len(toks) >= 2 and toks[1].lstrip("-").isdigit():
                    idx = int(toks[1])
                    labels[idx] = " ".join(toks[2:]) if len(toks) > 2 else ""
                continue
            if first in _QDP_CMDS:
                continue
            try:
                vals = [float(t) for t in toks]
            except ValueError:
                continue
            data.append(vals)
    ncol = (max(labels) + 1) if labels else 0
    sums = [0.0] * ncol
    for row in data:
        if len(row) == ncol:
            for i in range(ncol):
                sums[i] += row[i]
    rows = []
    for i in sorted(labels):
        rows.append(("qdp", labels[i], fmt_num(sums[i])))
    return rows


def parse_wcnf(path):
    """instance.wcnf -> parsed counts and optimal MaxSAT objective."""
    rows = []
    nvar = ncl = top = 0
    clauses = []
    with open(path) as f:
        for ln in f:
            s = ln.strip()
            if not s:
                continue
            if s.startswith("p "):
                parts = s.split()
                if len(parts) >= 5 and parts[1] == "wcnf":
                    nvar = int(parts[2])
                    ncl = int(parts[3])
                    top = int(parts[4])
                continue
            toks = s.split()
            if not toks:
                continue
            weight = int(toks[0])
            lits = [int(x) for x in toks[1:] if x != "0"]
            lits = [x for x in lits if x != 0]
            clauses.append((weight, lits))
    hard = sum(1 for w, _ in clauses if w == top)
    soft = len(clauses) - hard
    # optimal MaxSAT objective by brute force over assignments
    best = None
    for mask in range(1 << nvar):
        truth = {v: bool(mask & (1 << (v - 1))) for v in range(1, nvar + 1)}
        cost = 0
        ok = True
        for weight, lits in clauses:
            sat = any((l > 0 and truth[l]) or (l < 0 and not truth[-l])
                      for l in lits)
            if not sat:
                if weight == top:
                    ok = False
                    break
                cost += weight
        if not ok:
            continue
        if best is None or cost < best:
            best = cost
    if best is None:
        best = top
    rows.append(("cnf", "vars", str(nvar)))
    rows.append(("cnf", "hard", str(hard)))
    rows.append(("cnf", "soft", str(soft)))
    rows.append(("cnf", "opt", str(best)))
    return rows


def main():
    args = sys.argv[1:]
    indir = args[0] if len(args) >= 1 else IN_DIR
    out = args[1] if len(args) >= 2 else OUT_TSV

    rows = []
    rows += parse_people(os.path.join(indir, "people.tsv"))
    rows += parse_prefs(indir)
    rows += parse_addresses(os.path.join(indir, "addresses.txt"))
    rows += parse_tree(os.path.join(indir, "dirlist.txt"))
    rows += parse_qdp(os.path.join(indir, "table.qdp"))
    rows += parse_wcnf(os.path.join(indir, "instance.wcnf"))

    rows.sort(key=lambda r: (r[0], r[1]))
    with open(out, "w") as f:
        for typ, key, val in rows:
            f.write("%s\t%s\t%s\n" % (typ, key, val))


if __name__ == "__main__":
    main()
