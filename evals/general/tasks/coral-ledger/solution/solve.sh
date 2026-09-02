#!/bin/bash
# Oracle for coral-ledger: write the read-only analytics program to
# /app/solve.py and run it on the shipped ledger to produce /app/answer.json.
# Never reads /tests.
set -eu

TARGET="/app/solve.py"
OUT="/app/answer.json"

cat > "$TARGET" <<'PY'
"""Reference read-only analytics for the coral-ledger ledger DB.

Usage: python3 solve.py <db_path> <out_json>

Opens the database STRICTLY read-only (file:...?mode=ro) and answers the
five release questions from the ledger itself (including the analysis
window stored in the `params` table). The database file must remain
byte-for-byte untouched: no writes, no temp tables on disk, no sidecar
journal files.
"""
import json
import sqlite3
import sys
from datetime import datetime


def load_answer(db_path):
    con = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
    try:
        cur = con.cursor()
        params = dict(cur.execute("SELECT key, value FROM params").fetchall())
        lo, hi = params["window_from"], params["window_to"]

        # 1. average dwell (hours) of completed port calls arriving in-window
        dwell = {}
        for port, arrive, depart in cur.execute(
                "SELECT port, arrive_ts, depart_ts FROM port_calls"):
            if arrive is None or depart is None:
                continue
            if not (lo <= arrive[:10] <= hi):
                continue
            hours = (datetime.fromisoformat(depart)
                     - datetime.fromisoformat(arrive)).total_seconds() / 3600.0
            dwell.setdefault(port, []).append(hours)
        dwell_by_port = {p: round(sum(v) / len(v), 2)
                         for p, v in sorted(dwell.items())}

        # 2. top commodity by tonnage over voyages departing in-window
        totals = {}
        for commodity, tons in cur.execute(
                "SELECT c.commodity, c.weight_tons FROM cargo c "
                "JOIN voyages v ON c.voyage_id = v.id "
                "WHERE v.depart_date BETWEEN ? AND ?", (lo, hi)):
            totals[commodity] = totals.get(commodity, 0) + tons
        if totals:
            best = max(sorted(totals), key=lambda k: totals[k])
            top_commodity = {"commodity": best, "total_tons": totals[best]}
        else:
            top_commodity = {"commodity": None, "total_tons": 0}

        # 3. duplicate bills of lading
        dup = cur.execute(
            "SELECT bill_of_lading, COUNT(*) AS n FROM cargo "
            "GROUP BY bill_of_lading HAVING n > 1").fetchall()
        duplicate_bol = {"bols": len(dup),
                         "excess_rows": sum(n - 1 for _, n in dup)}

        # 4. flag mix: distinct vessels with an in-window port call
        rows = cur.execute(
            "SELECT ve.flag, COUNT(DISTINCT ve.id) FROM port_calls pc "
            "JOIN voyages vo ON pc.voyage_id = vo.id "
            "JOIN vessels ve ON vo.vessel_id = ve.id "
            "WHERE substr(pc.arrive_ts, 1, 10) BETWEEN ? AND ? "
            "GROUP BY ve.flag", (lo, hi)).fetchall()
        flag_mix = [[flag, n] for flag, n in
                    sorted(rows, key=lambda r: (-r[1], r[0]))]

        # 5. vessels that never called in-window
        active = {vid for (vid,) in cur.execute(
            "SELECT DISTINCT vo.vessel_id FROM port_calls pc "
            "JOIN voyages vo ON pc.voyage_id = vo.id "
            "WHERE substr(pc.arrive_ts, 1, 10) BETWEEN ? AND ?", (lo, hi))}
        idle_vessels = sorted(name for vid, name in cur.execute(
            "SELECT id, name FROM vessels") if vid not in active)

        return {
            "dwell_by_port": dwell_by_port,
            "top_commodity": top_commodity,
            "duplicate_bol": duplicate_bol,
            "flag_mix": flag_mix,
            "idle_vessels": idle_vessels,
        }
    finally:
        con.close()


def main(argv):
    if len(argv) != 3:
        print("usage: python3 solve.py <db_path> <out_json>", file=sys.stderr)
        return 2
    answer = load_answer(argv[1])
    with open(argv[2], "w", encoding="utf-8") as fh:
        json.dump(answer, fh, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

# Run the program on the shipped visible ledger to produce the deliverable.
python3 "$TARGET" /app/data/port.db "$OUT"

# Integrity self-check: no sidecar files left next to the ledger.
for side in /app/data/port.db-wal /app/data/port.db-shm /app/data/port.db-journal; do
    test ! -e "$side"
done

echo "solve.sh done -> $TARGET and $OUT"
python3 -c "import json; d=json.load(open('$OUT')); print({k: (len(v) if isinstance(v,(dict,list)) else v) for k,v in d.items()})"
