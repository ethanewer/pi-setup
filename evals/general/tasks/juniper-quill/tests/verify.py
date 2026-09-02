#!/usr/bin/env python3
"""Verifier (ground-truth recomputation) for juniper-quill.

This module re-derives the expected cleaned customer rows and audit shape from
a damaged BrightShard warehouse independently of the agent implementation, then
compares the agent's /app artifacts (visible) or a hidden-case workdir against
that ground truth. Called by tests/test.sh.
"""
import csv
import glob
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

WAL_MAGIC = bytes([0x37, 0x7f, 0x06, 0x82])
N_TRIALS = 20
CSV_HEADER = ["id", "name", "email", "phone", "value", "balance"]
PERF_QUERY = "SELECT COUNT(*) FROM audit WHERE balance BETWEEN 300000 AND 305000"

# Declared deliverables this checker executes (visible /app workdir) and, where
# they are data artifacts rather than programs, validates semantically:
#   - /app/merged.json            (parsed, dedup/order/type/count-checked)
#   - /app/trial_*.csv            (all 20 trial CSVs compared to clean table)
#   - /app/warehouse/clean.db     (reopened and compared to the exports + audit)
#   - /app/fd.txt                 (byte-compared to the golden content)
# The /app/recover.py program itself is executed on the visible and every hidden
# workdir in run_agent_on().


def xor_decode(data, key):
    if not key:
        return data
    return bytes(data[i] ^ key[i % 4] for i in range(len(data)))


def detect_key(wal_path):
    with open(wal_path, "rb") as f:
        hdr = f.read(4)
    return bytes(h ^ m for h, m in zip(hdr, WAL_MAGIC))


def ground_truth(wh):
    """Independently derive expected cleaned rows + audit shape from wh."""
    key = detect_key(os.path.join(wh, "inventory.db-wal"))
    with open(os.path.join(wh, "inventory.db"), "rb") as f:
        raw = f.read()
    tmp = tempfile.mkstemp(suffix=".db")[1]
    try:
        with open(tmp, "wb") as f:
            f.write(xor_decode(raw, key))
        con = sqlite3.connect(tmp)
        rows = con.execute(
            "SELECT id,name,email,phone,value,balance FROM customers").fetchall()
        kept = []
        for cid, name, email, phone, value, balance in rows:
            name = name.lower()
            email = "" if email is None else email
            phone = "" if phone is None else phone
            if email == "" and phone == "":
                continue
            kept.append((cid, name, email, phone, int(value), int(balance)))
        best = {}
        for c in kept:
            cid = c[0]
            tkey = (c[1], c[2], c[3], int(c[4]), int(c[5]))
            if cid not in best or tkey < best[cid][0]:
                best[cid] = (tkey, c)
        cleaned = [best[cid][1] for cid in best]
        cleaned.sort(key=lambda c: c[0])
        audit = con.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='audit'"
        ).fetchone()
        audit_count = None
        qresult = None
        if audit:
            audit_count = con.execute("SELECT COUNT(*) FROM audit").fetchone()[0]
            qresult = con.execute(PERF_QUERY).fetchone()[0]
        con.close()
        return cleaned, audit_count, qresult
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def read_csv_rows(path):
    with open(path, newline="") as f:
        rd = csv.reader(f)
        header = next(rd)
        out = []
        for row in rd:
            if not row or (len(row) == 1 and row[0].strip() == ""):
                continue
            out.append((int(row[0]), row[1], row[2], row[3],
                        int(row[4]), int(row[5])))
    return header, out


def check_workdir(target, expected, audit_shape, verbose=True):
    """Run semantic checks on one recovered workdir."""
    cleaned, audit_count, qresult = expected
    fails = []

    def chk(name, ok, detail=""):
        if not ok:
            fails.append((name, detail))
            if verbose:
                print("  FAIL %s %s" % (name, detail))
        # else silently pass

    # 1) merged.json
    mj = os.path.join(target, "merged.json")
    if not os.path.isfile(mj):
        chk("merged.json exists", False, "missing")
    else:
        try:
            with open(mj) as f:
                data = json.load(f)
            assert isinstance(data, list), "not a list"
            got = []
            for it in data:
                assert set(it.keys()) == {"id", "name", "value"}, "bad keys"
                assert isinstance(it["id"], int), "id not int"
                assert isinstance(it["name"], str), "name not str"
                assert isinstance(it["value"], int), "value not int"
                got.append((it["id"], it["name"], it["value"]))
            want = [(c[0], c[1], c[4]) for c in cleaned]
            chk("merged.json count", len(got) == len(want),
                "%d vs %d" % (len(got), len(want)))
            ids = [g[0] for g in got]
            chk("merged.json no-dup-ids", len(set(ids)) == len(ids))
            chk("merged.json sorted ascending", ids == sorted(ids))
            chk("merged.json row set", sorted(got) == sorted(want))
            chk("merged.json types-only-fields", True)
        except Exception as e:
            chk("merged.json parse", False, repr(e))

    # 2) trial CSVs (exactly N_TRIALS, each matching the clean table)
    trials = sorted(glob.glob(os.path.join(target, "trial_*.csv")))
    chk("trial csv count", len(trials) == N_TRIALS, "got %d" % len(trials))
    seen_names = set()
    for i, p in enumerate(trials):
        base = os.path.basename(p)
        chk("trial csv naming %s" % base,
            base.startswith("trial_") and base.endswith(".csv") and
            base[6:-4].isdigit(), base)
        seen_names.add(base)
        want_names = {"trial_%d.csv" % t for t in range(1, N_TRIALS + 1)}
        chk("trial csv nameset", seen_names.issubset(want_names))
        header, rows = read_csv_rows(p)
        chk("trial csv header %s" % base, header == CSV_HEADER, str(header))
        chk("trial csv rows %s" % base, rows == cleaned, "%d vs %d" % (len(rows), len(cleaned)))
        chk("trial csv sorted %s" % base, [r[0] for r in rows] == sorted(r[0] for r in rows))

    # 3) clean.db consistency (database == exported CSV)
    cdb = os.path.join(target, "warehouse", "clean.db")
    if not os.path.isfile(cdb):
        chk("clean.db exists", False, "missing")
    else:
        try:
            con = sqlite3.connect(cdb)
            rows = con.execute(
                "SELECT id,name,email,phone,value,balance FROM customers").fetchall()
            rows = [(r[0], r[1], r[2] if r[2] else "", r[3] if r[3] else "",
                     int(r[4]), int(r[5])) for r in rows]
            chk("clean.db customers == expected", rows == cleaned,
                "%d vs %d" % (len(rows), len(cleaned)))
            chk("clean.db customers sorted",
                [r[0] for r in rows] == sorted(r[0] for r in rows))
            # db vs every trial csv
            db_set = set(rows)
            for base in sorted(os.listdir(target)):
                if base.startswith("trial_") and base.endswith(".csv"):
                    _, prow = read_csv_rows(os.path.join(target, base))
                    chk("db==csv %s" % base, set(prow) == db_set)
            con.close()
        except Exception as e:
            chk("clean.db read", False, repr(e))

    # 4) audit shape + performance (only meaningful on /app visible workdir)
    if audit_shape:
        cdb = os.path.join(target, "warehouse", "clean.db")
        try:
            con = sqlite3.connect(cdb)
            if con.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='audit'").fetchone() is None:
                chk("audit table exists", False, "missing")
                con.close()
            else:
                ac = con.execute("SELECT COUNT(*) FROM audit").fetchone()[0]
                chk("audit count", ac == audit_count, "%d vs %d" % (ac, audit_count))
                qr = con.execute(PERF_QUERY).fetchone()[0]
                chk("audit query result", qr == qresult, "%s vs %s" % (qr, qresult))
                # timing gate: warm-up then min-of-runs on agent's db vs indexed copy
                def time_db(conn):
                    for _ in range(3):
                        conn.execute(PERF_QUERY).fetchall()
                    ts = []
                    for _ in range(7):
                        t0 = time.monotonic()
                        conn.execute(PERF_QUERY).fetchall()
                        ts.append(time.monotonic() - t0)
                    return min(ts)
                t_agent = time_db(con)
                con.close()
                refp = tempfile.mkstemp(suffix=".db")[1]
                try:
                    shutil.copyfile(cdb, refp)
                    rcon = sqlite3.connect(refp)
                    rcon.execute("CREATE INDEX IF NOT EXISTS idx_audit_balance ON audit(balance)")
                    rcon.commit()
                    t_ref = time_db(rcon)
                    rcon.close()
                finally:
                    if os.path.exists(refp):
                        os.remove(refp)
                limit = max(t_ref * 8.0, 0.005)
                chk("audit timing gate",
                    t_agent <= limit and t_agent < 0.05,
                    "agent=%.6fs ref=%.6fs limit=%.6fs" % (t_agent, t_ref, limit))
        except Exception as e:
            chk("perf check", False, repr(e))
    return fails


def run_agent_on(target):
    """Run the delivered /app/recover.py on TARGET, return True on success."""
    r = subprocess.run(["python3", "/app/recover.py", target],
                       capture_output=True, text=True)
    return r.returncode == 0


def main():
    verbose = True
    all_fails = []
    audit_expected = None

    # ---- visible /app workdir ----
    if not os.path.isfile("/app/recover.py"):
        print("FATAL: /app/recover.py missing")
        return 1
    vt = ground_truth("/app/warehouse")
    print("visible expected cleaned rows: %d" % len(vt[0]))
    f = check_workdir("/app", vt, True, verbose)
    all_fails += f

    # ---- fd recovery ----
    fd_expected = "/tests/fd_golden.txt"
    if os.path.isfile("/app/fd.txt") and os.path.isfile(fd_expected):
        with open("/app/fd.txt", "rb") as a, open(fd_expected, "rb") as b:
            if a.read() != b.read():
                all_fails.append(("fd.txt content", "mismatch"))
                print("  FAIL fd.txt content")
    else:
        all_fails.append(("fd.txt exists", "missing or no golden"))
        print("  FAIL fd.txt exists")
    # Also confirm the keeper really exposed a deleted descriptor (anti-cheat).
    # Kept as informational (soft) so a correct agent is never falsely failed if
    # the host skips the image ENTRYPOINT; the content gate above stays strict.
    pidfile = "/tmp/juniper-lockbox/keeper.pid"
    if os.path.isfile(pidfile):
        with open(pidfile) as f:
            pid = f.read().strip()
        fd_dir = "/proc/%s/fd" % pid if os.path.isdir("/proc/" + pid) else ""
        deleted = False
        if fd_dir and os.path.isdir(fd_dir):
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(os.path.join(fd_dir, fd))
                    if "lost.csv" in link and "(deleted)" in link:
                        deleted = True
                except OSError:
                    pass
        print("INFO keeper %s holds deleted lost.csv: %s" % (pid, deleted))
    else:
        print("INFO keeper not running (fd anti-cheat skipped)")

    # ---- hidden cases ----
    for name in sorted(os.listdir("/tests/hidden")):
        src = os.path.join("/tests/hidden", name, "warehouse")
        if not os.path.isdir(src):
            continue
        tgt = "/tmp/run_%s" % name
        shutil.rmtree(tgt, ignore_errors=True)
        os.makedirs(tgt)
        shutil.copytree(src, os.path.join(tgt, "warehouse"))
        if not run_agent_on(tgt):
            all_fails.append(("hidden run %s" % name, "recover.py failed"))
            print("  FAIL hidden run %s: recover.py failed" % name)
            continue
        exp = ground_truth(os.path.join(tgt, "warehouse"))
        print("hidden %s expected rows: %d" % (name, len(exp[0])))
        f = check_workdir(tgt, exp, False, verbose)
        for nm, det in f:
            all_fails.append(("hidden %s %s" % (name, nm), det))

    print("TOTAL FAILS:", len(all_fails))
    return 1 if all_fails else 0


if __name__ == "__main__":
    sys.exit(main())
