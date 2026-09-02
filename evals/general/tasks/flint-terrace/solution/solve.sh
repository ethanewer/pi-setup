#!/bin/bash
# Oracle for flint-terrace.
# Writes the real recovery program /app/solve.py and RUNS it on the visible
# scenario (/app) to produce all deliverables. Never reads /tests.
set -eu

cat > /app/solve.py <<'ORACLE_PY'
#!/usr/bin/env python3
"""solve.py -- Flint-Crest Observatory recovery workbench.

Given a scenario directory it rebuilds a consolidated SQLite catalog and emits
every deliverable. Specifically it:

  1) bulk-loads catalog.csv through the client-side COPY command (sqlite .import)
  2) salvages the intact rows from a byte-truncated SQLite file (direct B-tree)
     and serialises them to salvage.json
  3) reads / auto-replays the un-applied WAL into the merged catalog table
  4) writes the aggregate-under-HAVING + domain-filter summary query
  5) rewrites the legacy (non-SQLite) query to a SQLite-valid equivalent
  6) writes the prescribed CREATE TABLE (schema.sql)

Usage: python3 solve.py <input_dir> <output_dir>
"""
import sys, os, json, re, struct, sqlite3, subprocess, shutil

SCHEMA = (
    "CREATE TABLE catalog (\n"
    "  id          INTEGER PRIMARY KEY,\n"
    "  domain      TEXT    NOT NULL,\n"
    "  site        TEXT    NOT NULL,\n"
    "  recorded_on TEXT    NOT NULL,\n"
    "  reading     REAL    NOT NULL\n"
    ");\n"
)

ALLOWED = {"astronomy", "physics", "geology"}
HAVING_N = 2

SUMMARY_SQL = (
    "SELECT site, COUNT(*) AS n\n"
    "FROM catalog\n"
    "WHERE domain IN ('astronomy','physics','geology')\n"
    "GROUP BY site\n"
    "HAVING COUNT(*) >= 2\n"
    "ORDER BY site;"
)


# ------------------------------------------------------------- byte helpers
def varint(data, i):
    r = 0
    while True:
        c = data[i]
        i += 1
        r = (r << 7) | (c & 0x7F)
        if c < 0x80:
            return r, i


def u16(data, i):
    return struct.unpack(">H", data[i:i + 2])[0]


def u32(data, i):
    return struct.unpack(">I", data[i:i + 4])[0]


def btree_off(page, ps):
    return (page - 1) * ps + (100 if page == 1 else 0)


def serial_types(blob, i):
    header, i = varint(blob, i)
    end = i + header - 1
    types = []
    while i < end:
        t, i = varint(blob, i)
        types.append(t)
    return types, i


def decode_value(t, blob, i):
    if t == 0:
        return None, i
    if t == 1:
        b = blob[i]
        return (b - 256 if b >= 128 else b), i + 1
    if 2 <= t <= 4:
        return int.from_bytes(blob[i:i + t], "big"), i + t
    if t == 5:
        return int.from_bytes(blob[i:i + 6], "big"), i + 6
    if t == 6:
        return int.from_bytes(blob[i:i + 8], "big", signed=True), i + 8
    if t == 7:
        return struct.unpack(">d", blob[i:i + 8])[0], i + 8
    if t == 8:
        return 0, i
    if t == 9:
        return 1, i
    n = (t - 12) // 2 if t % 2 == 0 else (t - 13) // 2
    return blob[i:i + n].decode("utf-8"), i + n


def decode_leaf_cell(blob, off):
    _len, i = varint(blob, off)
    rowid, i = varint(blob, i)
    types, i = serial_types(blob, i)
    vals = []
    for t in types:
        v, i = decode_value(t, blob, i)
        vals.append(v)
    return rowid, vals


def page_type(blob, ps, page):
    return blob[btree_off(page, ps)] & 0x0F


def leaf_rows(blob, ps, page):
    base = btree_off(page, ps)
    ncell = u16(blob, base + 3)
    pstart = base + 8
    out = []
    for c in range(ncell):
        p = u16(blob, pstart + c * 2)
        out.append(decode_leaf_cell(blob, (page - 1) * ps + p))
    out.sort()
    return out


def tree_rows(blob, ps, page, npc):
    t = page_type(blob, ps, page)
    if t == 13:
        return leaf_rows(blob, ps, page)
    if t == 5:  # interior table
        base = btree_off(page, ps)
        ncell = u16(blob, base + 3)
        pstart = base + 12
        right = u32(blob, base + 8)
        cells = []
        for c in range(ncell):
            p = u16(blob, pstart + c * 2)
            cells.append(u32(blob, (page - 1) * ps + p))
        cells.append(right)
        acc = []
        for ch in cells:
            if ch <= npc:
                acc.extend(tree_rows(blob, ps, ch, npc))
        acc.sort()
        return acc
    return []


def table_root(blob, ps, name):
    base = btree_off(1, ps)
    ncell = u16(blob, base + 3)
    pstart = base + 8
    for c in range(ncell):
        p = u16(blob, pstart + c * 2)
        _rowid, vals = decode_leaf_cell(blob, p)
        if len(vals) >= 5 and str(vals[2]) == name:
            return vals[3]
    raise KeyError("table %r not found" % name)


def salvage_rows(path, table="catalog"):
    raw = open(path, "rb").read()
    ps = struct.unpack(">H", raw[16:18])[0] if len(raw) >= 18 else 0
    declared = struct.unpack(">I", raw[28:32])[0] if len(raw) >= 32 else 0
    npc = len(raw) // ps if ps else 0
    if not ps or npc < 1:
        return [], ps, npc, declared
    try:
        root = table_root(raw, ps, table)
    except KeyError:
        return [], ps, npc, declared
    if root > npc:
        return [], ps, npc, declared
    acc = []
    for rowid, vals in tree_rows(raw, ps, root, npc):
        if len(vals) >= 2 and vals[0] is None:
            vals = vals[1:]
        acc.append([int(rowid)] + list(vals[:4]))
    acc.sort(key=lambda q: q[0])
    return acc, ps, npc, declared


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)


def replay_min_wal(in_dir, out_dir, loglines):
    src = os.path.join(in_dir, "wal.db")
    if not os.path.exists(src):
        loglines.append("WAL: no wal.db present, nothing to replay")
        return []
    dst = os.path.join(out_dir, "_wal")
    if os.path.exists(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    shutil.copy(src, os.path.join(dst, "wal.db"))
    for extra in ("wal.db-wal", "wal.db-shm"):
        p = os.path.join(in_dir, extra)
        if os.path.exists(p):
            shutil.copy(p, os.path.join(dst, extra))
    con = sqlite3.connect(os.path.join(dst, "wal.db"))
    rows = con.execute(
        "SELECT id,domain,site,recorded_on,reading FROM catalog ORDER BY id"
    ).fetchall()
    con.close()
    shutil.rmtree(dst)
    loglines.append("WAL: replayed %d rows from wal.db (auto WAL replay)" % len(rows))
    return rows


def fix_query(legacy):
    out = legacy
    out = re.sub(
        r"\bOFFSET\s+(\d+)\s+ROWS\s+FETCH\s+NEXT\s+(\d+)\s+ROWS\s+ONLY",
        lambda m: "LIMIT %s OFFSET %s" % (m.group(2), m.group(1)), out, flags=re.I)
    out = re.sub(
        r"\bFETCH\s+(?:FIRST|NEXT)\s+(\d+)\s+ROWS\s+ONLY",
        lambda m: "LIMIT %s" % m.group(1), out, flags=re.I)
    out = re.sub(
        r"\b((?:[A-Za-z_]\w*)\s*\([^)]*\)|[A-Za-z_]\w*(?:\.[A-Za-z_\w]+)?)\s*::\s*"
        r"(NUMERIC|REAL|INTEGER|INT|BIGINT|TEXT|DATE)\b",
        lambda m: "CAST(%s AS %s)" % (m.group(1).strip(), m.group(2).upper()),
        out, flags=re.I)
    return out


def jflo(x):
    try:
        return round(float(x), 6)
    except (TypeError, ValueError):
        return 0.0


def load_csv_copy(in_dir, out_dir, loglines):
    """Imports catalog.csv into a scratch db via the SQLite client-side COPY
    (the .import dot-command). The bulk load is genuinely a client COPY,
    evidenced in the returned rows and the import_log transcript."""
    csv = os.path.join(in_dir, "catalog.csv")
    if not os.path.exists(csv):
        return []
    stage = os.path.join(out_dir, "_stage.db")
    if os.path.exists(stage):
        os.unlink(stage)
    script = (
        "CREATE TABLE s(id INTEGER, domain TEXT, site TEXT, "
        "recorded_on TEXT, reading REAL);\n"
        ".mode csv\n"
        ".import --skip 1 \"%s\" s\n" % csv
    )
    r = subprocess.run(["sqlite3", stage], input=script, text=True,
                       capture_output=True)
    if (r.returncode != 0 or not os.path.exists(stage)):
        # fallback for a CLI without --skip: strip the header, then import
        body = open(csv).read().splitlines()
        headless = os.path.join(out_dir, "_headless.csv")
        with open(headless, "w") as f:
            f.write("\n".join(body[1:]) + ("\n" if len(body) > 1 else ""))
        script2 = (
            "CREATE TABLE s(id TEXT PRIMARY KEY, domain TEXT, site TEXT, "
            "recorded_on TEXT, reading REAL);\n.mode csv\n"
            ".import \"%s\" s\n" % headless)
        subprocess.run(["sqlite3", stage], input=script2, text=True,
                       capture_output=True)
        if os.path.exists(headless):
            os.unlink(headless)
    if not os.path.exists(stage):
        return []
    con = sqlite3.connect(stage)
    rows = con.execute("SELECT id,domain,site,recorded_on,reading FROM s").fetchall()
    con.close()
    if os.path.exists(stage):
        os.unlink(stage)
    loglines.append("client COPY: loaded %d rows from catalog.csv via the SQLite "
                    "client dot-command .import (client-side COPY)" % len(rows))
    return rows


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: python3 solve.py <input_dir> <output_dir>\n")
        return 2
    in_dir = os.path.abspath(argv[1])
    out_dir = os.path.abspath(argv[2])
    os.makedirs(out_dir, exist_ok=True)
    loglines = []

    csv_rows = load_csv_copy(in_dir, out_dir, loglines)

    salvage = []
    salvage_meta = {
        "source": "legacy.db",
        "intact_rows": 0,
        "retained_bytes": 0,
        "declared_pages": 0,
    }
    legacy_path = os.path.join(in_dir, "legacy.db")
    if os.path.exists(legacy_path):
        salvage, ps, npc, declared = salvage_rows(legacy_path)
        salvage_meta = {
            "source": "legacy.db",
            "intact_rows": len(salvage),
            "retained_bytes": os.path.getsize(legacy_path),
            "declared_pages": declared,
            "page_size": ps,
        }
    salvage_json = [
        {"id": r[0], "domain": r[1], "site": r[2], "recorded_on": r[3],
         "reading": jflo(r[4])}
        for r in salvage
    ]
    with open(os.path.join(out_dir, "salvage.json"), "w") as f:
        json.dump({"diagnosis": salvage_meta, "salvaged": salvage_json}, f, indent=2)

    wal_rows = replay_min_wal(in_dir, out_dir, loglines)

    con = sqlite3.connect(os.path.join(out_dir, "recovered.db"))
    con.execute(SCHEMA)
    cur = con.cursor()
    merged = {}
    for r in csv_rows:
        merged[int(r[0])] = (int(r[0]), str(r[1]), str(r[2]), str(r[3]), jflo(r[4]))
    for r in salvage:
        if len(r) >= 5:
            merged[int(r[0])] = (int(r[0]), str(r[1]), str(r[2]), str(r[3]),
                                 jflo(r[4]))
    for r in wal_rows:
        merged[int(r[0])] = (int(r[0]), str(r[1]), str(r[2]), str(r[3]),
                             jflo(r[4]))
    for pid in sorted(merged):
        row = merged[pid]
        cur.execute(
            "INSERT OR REPLACE INTO catalog(id,domain,site,recorded_on,reading)"
            " VALUES(?,?,?,?,?)", row)
    con.commit()
    con.close()

    with open(os.path.join(out_dir, "summary.sql"), "w") as f:
        f.write(SUMMARY_SQL + "\n")

    legacy_q = os.path.join(in_dir, "legacy_query.sql")
    fixed = SUMMARY_SQL
    if os.path.exists(legacy_q):
        with open(legacy_q) as f:
            leg = f.read()
        fixed = fix_query(leg)
    with open(os.path.join(out_dir, "fixed_query.sql"), "w") as f:
        f.write(fixed + "\n")

    with open(os.path.join(out_dir, "schema.sql"), "w") as f:
        f.write(SCHEMA)

    with open(os.path.join(out_dir, "import_log.txt"), "w") as f:
        f.write("\n".join(loglines) + "\n")

    for sc in ("_stage.db", "_wal"):
        p = os.path.join(out_dir, sc)
        if os.path.isdir(p):
            shutil.rmtree(p)
        elif os.path.exists(p):
            os.unlink(p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
ORACLE_PY
chmod +x /app/solve.py

python3 /app/solve.py /app /app

echo "oracle done: wrote /app/solve.py, /app/schema.sql, /app/recovered.db,"
echo "  /app/salvage.json, /app/summary.sql, /app/fixed_query.sql, /app/import_log.txt"