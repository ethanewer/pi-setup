#!/bin/bash
# calm-bridge oracle: writes the deliverable, builds the visible + trial
# scenarios with /app/files/tool/gen.py, then RUNS /app/recover.py to produce
# every required /app artifact. It never reads /tests.
set -eu

# 1) the deliverable: the actual recovery program
cat > /app/recover.py <<'RECOVERPY'
#!/usr/bin/env python3
"""calm-bridge recovery + cleaning + export.

Recoverable tool for the "forlorn ledger" scenario. It is importable and also
has a CLI:

  python3 recover.py run  <db> <journal> <out.json>
      Reverse the byte transform on *journal*, merge its rows with the intact
      rows read from *db*, apply the in-database cleaning pipeline, then write
      the id-sorted, id-unique, cleaned rows as JSON to *out.json*.

  python3 recover.py csv  <db> <journal>
      Same recovery + cleaning, but prints CSV rows to stdout (for trials).

  python3 recover.py fd   <seed_file> <out>
      Recover the content of an unlinked-but-open file descriptor -> *out*.

  python3 recover.py perf <scaled_db>
      Warm up, then time one indexed query on a large metrics table and print
      the elapsed milliseconds (integer) to stdout.

The format is fully specified in /app/instruction.md.
"""
import os
import sys
import json
import time
import sqlite3
import tempfile

MAGIC = "WJNT1"                 # first line of a native (untransformed) journal
FIELDS = ["id", "name", "msisdn", "email", "phone", "region"]


def digits(value):
    """ASCII 0-9 substring of *value* ('' when there are none)."""
    if value is None:
        return ""
    return "".join(c for c in str(value) if "0" <= c <= "9")


# ---------------------------------------------------------------------------
# Damaged journal: detect + reverse the byte transform, then parse records.
# ---------------------------------------------------------------------------
def parse_journal(blob):
    """Parse native journal bytes -> list of row dicts (skipping bad lines)."""
    text = blob.decode("utf-8", errors="replace")
    lines = text.splitlines()
    rows = []
    if not lines:
        return rows
    for ln in lines[1:]:
        parts = ln.split("\t")
        if len(parts) != len(FIELDS):
            continue                        # malformed record -> skip, keep rest
        try:
            rid = int(parts[0])
        except ValueError:
            continue
        if rid < 1:
            continue
        rows.append(dict(id=rid, name=parts[1].strip(), msisdn=parts[2].strip(),
                         email=parts[3].strip(), phone=parts[4].strip(),
                         region=parts[5].strip()))
    return rows


def reverse_journal(blob):
    """Return (rows, key). Detect a single-byte XOR transform from the header.

    A transformed journal's header no longer equals the native magic, so every
    XOR key 0..255 is tried; the one making the leading bytes match the native
    magic is the reverse transform. If none matches the stream is treated as
    already native (key 0).
    """
    magic = (MAGIC + "\n").encode()
    for key in range(1, 256):
        cand = bytes(b ^ key for b in blob)
        if cand.startswith(magic):
            return parse_journal(cand), key
    if blob.startswith(magic):
        return parse_journal(blob), 0
    return [], 0


# ---------------------------------------------------------------------------
# SQL-side cleaning. Every transformation is a real SQL statement executed on an
# in-memory SQLite engine, so the persistence/evidence of the cleaning lives in
# the database statements themselves.
# ---------------------------------------------------------------------------
def clean_with_sql(merged_rows):
    conn = sqlite3.connect(":memory:")
    conn.create_function("wal_digits", 1, digits)
    conn.execute("CREATE TABLE contacts(id INTEGER, name TEXT, msisdn TEXT, "
                 "email TEXT, phone TEXT, region TEXT, seq INTEGER)")
    data = [(r["id"], r.get("name") or "", r.get("msisdn") or "",
             r.get("email") or "", r.get("phone") or "", r.get("region") or "",
             i) for i, r in enumerate(merged_rows)]
    conn.executemany(
        "INSERT INTO contacts VALUES(?,?,?,?,?,?,?)", data)

    # 4) de-duplicate by id, keeping the first occurrence in input order
    conn.execute("CREATE TABLE dedup AS "
                 "SELECT id, name, msisdn, email, phone, region FROM ("
                 "  SELECT *, ROW_NUMBER() OVER "
                 "            (PARTITION BY id ORDER BY seq) rn "
                 "  FROM contacts) WHERE rn = 1")
    conn.execute("DROP TABLE contacts")
    conn.execute("ALTER TABLE dedup RENAME TO contacts")

    # 1) lower-case the text column (with trim)
    conn.execute("UPDATE contacts SET name = lower(trim(name))")
    # 2) digits-only extraction cast to a new integer column
    conn.execute("ALTER TABLE contacts ADD COLUMN msdig INTEGER")
    conn.execute(
        "UPDATE contacts SET msdig = "
        "CASE WHEN wal_digits(msisdn) = '' THEN NULL "
        "     ELSE CAST(wal_digits(msisdn) AS INTEGER) END")
    # 3) delete rows missing BOTH contact fields
    conn.execute("DELETE FROM contacts WHERE "
                 "COALESCE(email, '') = '' AND COALESCE(phone, '') = ''")

    out = []
    for rid, name, msisdn, email, phone, region, msdig in conn.execute(
            "SELECT id, name, msisdn, email, phone, region, msdig "
            "FROM contacts ORDER BY id"):
        out.append(dict(id=rid, name=name, msisdn=msisdn or "",
                        msisdn_d=msdig,
                        email=email or None, phone=phone or None,
                        region=region or ""))
    conn.close()
    return out


def read_db(dbpath):
    conn = sqlite3.connect(dbpath)
    rows = []
    for rid, name, msisdn, email, phone, region in conn.execute(
            "SELECT id, name, msisdn, email, phone, region "
            "FROM contacts ORDER BY id"):
        rows.append(dict(id=rid, name=name, msisdn=msisdn, email=email,
                         phone=phone, region=region))
    conn.close()
    return rows


def recover(db_path, journal_path):
    db_rows = read_db(db_path)
    if journal_path and os.path.exists(journal_path):
        with open(journal_path, "rb") as f:
            blob = f.read()
        jrows, key = reverse_journal(blob)
        merged = db_rows + jrows
    else:
        key = 0
        merged = db_rows
    return clean_with_sql(merged), key


def to_csv(rows):
    lines = ["id,name,msisdn,msisdn_d,email,phone,region"]
    for r in rows:
        lines.append(",".join([
            str(r["id"]), r["name"], r["msisdn"],
            "" if r["msisdn_d"] is None else str(r["msisdn_d"]),
            r["email"] or "", r["phone"] or "", r["region"]]))
    return "\n".join(lines) + "\n"


def recover_open_fd(seed_path, out_path):
    with open(seed_path, "rb") as f:
        content = f.read()
    with tempfile.NamedTemporaryFile("wb", delete=False) as tf:
        tf.write(content)
        tf.flush()
        path = tf.name
    fd = os.open(path, os.O_RDWR)         # hold the descriptor open
    os.unlink(path)                       # unlink the inode from the namespace
    buf = bytearray()
    while True:
        chunk = os.read(fd, 4096)
        if not chunk:
            break
        buf += chunk
    os.close(fd)
    with open(out_path, "wb") as f:
        f.write(buf)
    return buf


# --------------------------------------------------------------------------- #
def perf_report(db):
    conn = sqlite3.connect(db)
    conn.commit()
    conn.execute("CREATE INDEX IF NOT EXISTS idx_metrics_grp ON metrics(grp)")
    conn.commit()

    def q():
        return conn.execute(
            "SELECT COUNT(*) FROM metrics WHERE grp = 7").fetchone()[0]

    q(); q(); q()                             # warm-up caches / query plan
    t0 = time.perf_counter()
    n = q()
    ms = (time.perf_counter() - t0) * 1000.0
    conn.close()
    return int(round(ms)), n


def main(argv):
    args = argv[0:]
    if not args:
        print(__doc__, file=sys.stderr)
        return 1
    cmd = args[0]
    if cmd == "run":
        _, db, jrn, out = args
        rows, key = recover(db, jrn)
        with open(out, "w") as f:
            json.dump(rows, f)
        print("recovered {0} rows from {1} (transform key {2})".format(
            len(rows), db, key), file=sys.stderr)
    elif cmd == "csv":
        _, db, jrn = args
        rows, _key = recover(db, jrn)
        print(to_csv(rows))
    elif cmd == "fd":
        _, seed, out = args
        recover_open_fd(seed, out)
        print("fd recovered -> {0}".format(out), file=sys.stderr)
    elif cmd == "perf":
        _, db = args
        ms, _n = perf_report(db)
        print(ms)
    else:
        print(__doc__, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
RECOVERPY
chmod +x /app/recover.py
python3 -m py_compile /app/recover.py

# 2) build the visible scenario (deterministic seed) and recover -> merged.json
rm -rf /app/.wf
mkdir -p /app/.wf
python3 - <<'GENPY'
import sys, os, shutil
sys.path.insert(0, "/app/files")
from tool import gen as g
g.build_fixture("/app/.wf", 2029, 150)
os.makedirs("/app/trade", exist_ok=True)
shutil.copy("/app/.wf/ledger.db", "/app/trade/ledger.db")
shutil.copy("/app/.wf/ledger.wal", "/app/trade/ledger.wal")
GENPY
python3 /app/recover.py run /app/trade/ledger.db /app/trade/ledger.wal /app/merged.json

# 3) repeated recovery trials, each kept as a numbered CSV
trialseed=1
for no in 0001 0002 0003; do
  rm -rf /app/.tw; mkdir -p /app/.tw
  python3 - "$trialseed" <<'TPY'
import sys
sys.path.insert(0, "/app/files")
from tool import gen as g
g.build_fixture("/app/.tw", int(sys.argv[1]), 40)
TPY
  # one recovery trial -> a numbered deliverable under /app/trial_*.csv
  python3 /app/recover.py csv /app/.tw/ledger.db /app/.tw/ledger.wal > /app/trial_$no.csv
  trialseed=$((trialseed+1))
done
rm -rf /app/.tw

# 4) open-fd recovery -> fd.txt
python3 - <<'FDPY'
import sys
sys.path.insert(0, "/app/files")
from tool import gen as g
g.build_seed("/app/trade/service_draft.txt", 71)
FDPY
python3 /app/recover.py fd /app/trade/service_draft.txt /app/fd.txt

# 5) scaled db + prove the perf path runs
python3 - <<'SCPY'
import sys
sys.path.insert(0, "/app/files")
from tool import gen as g
g.build_scaled("/app/trade/scale.db", 300000)
SCPY
python3 /app/recover.py perf /app/trade/scale.db > /dev/null

rm -rf /app/.wf
echo "oracle done: recover.py, merged.json, trial_*.csv, fd.txt written"
