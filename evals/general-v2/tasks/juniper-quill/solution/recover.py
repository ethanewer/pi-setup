#!/usr/bin/env python3
"""Reference recovery pipeline for juniper-quill (BrightShard warehouse).

This is the real implementation of the task contract. It:
  1. Detects the 4-byte repeating XOR transform from the WAL header magic.
  2. Reverses it over the damaged database.
  3. Recovers the intact `customers` table and runs in-database cleaning
     (lowercase names, cast digits-only `value` to integer, dedup by id,
     drop rows that have neither contact field), sorting by id.
  4. Carries the operational `audit` table into the clean database and
     indexes `balance` so the timed query meets the performance gate.
  5. Exports 20 per-trial CSVs + merged.json.
  6. Reclaims the unlinked-but-open file descriptor's contents as fd.txt.
"""
import csv
import json
import os
import sqlite3
import sys
import tempfile
import time

WAL_MAGIC = bytes([0x37, 0x7f, 0x06, 0x82])
N_TRIALS = 20
CSV_HEADER = ["id", "name", "email", "phone", "value", "balance"]


def xor_decode(data: bytes, key: bytes) -> bytes:
    if not key:
        return data
    n = len(data)
    return bytes((data[i] ^ key[i % 4]) for i in range(n))


def detect_key(wal_path: str) -> bytes:
    with open(wal_path, "rb") as f:
        hdr = f.read(4)
    if len(hdr) != 4:
        sys.exit("cannot read WAL header at %s" % wal_path)
    key = bytes(h ^ m for h, m in zip(hdr, WAL_MAGIC))
    return key


def untransform(wh: str, decoded_path: str) -> None:
    key = detect_key(os.path.join(wh, "inventory.db-wal"))
    with open(os.path.join(wh, "inventory.db"), "rb") as f:
        raw = f.read()
    decoded = xor_decode(raw, key)
    with open(decoded_path, "wb") as f:
        f.write(decoded)


def clean_row(t):
    cid, name, email, phone, value, balance = t
    name = name.lower()
    email = "" if email is None else email
    phone = "" if phone is None else phone
    if email == "" and phone == "":
        return None
    iv = int(value)
    ib = int(balance)
    return (cid, name, email, phone, iv, ib)


def compute_cleaned(con) -> list:
    rows = con.execute("SELECT id,name,email,phone,value,balance FROM customers").fetchall()
    kept = []
    for t in rows:
        c = clean_row(t)
        if c is not None:
            kept.append(c)
    best = {}
    for c in kept:
        cid = c[0]
        key = (
            c[1],           # name (lowercased)
            c[2],           # email string
            c[3],           # phone string
            int(c[4]),      # value as int
            int(c[5]),      # balance as int
        )
        if cid not in best or key < best[cid][0]:
            best[cid] = (key, c)
    cleaned = [best[cid][1] for cid in best]
    cleaned.sort(key=lambda c: c[0])
    return cleaned


def write_outputs(target: str, cleaned: list, con) -> None:
    os.makedirs(target, exist_ok=True)
    # merged.json
    with open(os.path.join(target, "merged.json"), "w") as f:
        json.dump([{"id": c[0], "name": c[1], "value": c[4]} for c in cleaned], f)
    # trials
    for t in range(1, N_TRIALS + 1):
        with open(os.path.join(target, "trial_%d.csv" % t), "w", newline="") as f:
            w = csv.writer(f, lineterminator="\n")
            w.writerow(CSV_HEADER)
            for c in cleaned:
                w.writerow([c[0], c[1], c[2], c[3], c[4], c[5]])
    # clean database (fresh file next to the damaged source)
    con2 = sqlite3.connect(os.path.join(target, "warehouse", "clean.db"))
    con2.executescript(
        "CREATE TABLE customers(id INTEGER, name TEXT, email TEXT, phone TEXT,"
        " value INTEGER, balance INTEGER);"
    )
    con2.executemany("INSERT INTO customers VALUES (?,?,?,?,?,?)",
                     [tuple(c) for c in cleaned])
    con2.commit()
    # carry audit + tune it
    tbl = con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='audit'").fetchone()
    if tbl:
        audit_rows = con.execute("SELECT id,balance FROM audit").fetchall()
        con2.execute("CREATE TABLE audit(id INTEGER, balance INTEGER)")
        con2.executemany("INSERT INTO audit VALUES (?,?)", audit_rows)
        con2.commit()
        con2.execute("CREATE INDEX IF NOT EXISTS idx_audit_balance ON audit(balance)")
        con2.commit()
    con2.close()


def recover_fd(target: str) -> None:
    """Read the content of the unlinked-but-open descriptor held by keeper."""
    pidfile = "/tmp/juniper-lockbox/keeper.pid"
    content = None
    for _ in range(20):
        try:
            with open(pidfile) as f:
                pid = f.read().strip()
            if pid:
                fd_dir = "/proc/%s/fd" % pid
                if os.path.isdir(fd_dir):
                    for fd in os.listdir(fd_dir):
                        link = os.readlink(os.path.join(fd_dir, fd))
                        if "lost.csv" in link and "(deleted)" in link:
                            with open(os.path.join(fd_dir, fd), "rb") as f:
                                content = f.read()
                            break
        except FileNotFoundError:
            pass
        if content is not None:
            break
        time.sleep(0.5)
    if content is None:
        print("WARNING: could not reclaim open-file-descriptor content", flush=True)
        return
    with open(os.path.join(target, "fd.txt"), "wb") as f:
        f.write(content)


def main(target: str) -> None:
    wh = os.path.join(target, "warehouse")
    tmp = tempfile.mkstemp(suffix=".db", prefix="juniper_recovered_")[1]
    try:
        untransform(wh, tmp)
        con = sqlite3.connect(tmp)
        cleaned = compute_cleaned(con)
        write_outputs(target, cleaned, con)
        con.close()
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    recover_fd(target)


if __name__ == "__main__":
    tgt = sys.argv[1] if len(sys.argv) > 1 else "/app"
    main(tgt)
    print("recovery complete for %s" % tgt)
