#!/usr/bin/env python3
"""Export /app/data/dump_chain.db:accounts into /app/dump.csv (header row included).

Runs against the seeded dump_chain.db and writes the canonical CSV that the
verifier compares, normalized, against both the source CSV and the live DB table.
"""
import csv
import sqlite3

DB = "/app/data/dump_chain.db"
OUT = "/app/dump.csv"


def main() -> int:
    con = sqlite3.connect(DB)
    try:
        cur = con.cursor()
        try:
            # Normalized, id-ordered rows. Ordering by the integer id makes the
            # export deterministic regardless of insertion order.
            rows = cur.execute(
                "SELECT id, address, balance FROM accounts ORDER BY id"
            ).fetchall()
        except sqlite3.OperationalError:
            rows = []
    finally:
        con.close()

    with open(OUT, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["id", "address", "balance"])
        for rid, address, balance in rows:
            writer.writerow([str(int(rid)), str(address).strip(), str(int(balance))])
    return 0 if rows else 1


if __name__ == "__main__":
    raise SystemExit(main())