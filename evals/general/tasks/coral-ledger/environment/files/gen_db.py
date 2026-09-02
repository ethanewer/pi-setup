"""Deterministic fixture generator for the coral-ledger port ledger DB.

Usage: python3 gen_db.py <out.db> <seed>
"""
import random
import sqlite3
import sys
from datetime import datetime, timedelta

SCHEMA = """
CREATE TABLE vessels (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    flag TEXT NOT NULL,
    klass TEXT NOT NULL
);
CREATE TABLE voyages (
    id INTEGER PRIMARY KEY,
    vessel_id INTEGER NOT NULL REFERENCES vessels(id),
    origin_port TEXT NOT NULL,
    dest_port TEXT NOT NULL,
    depart_date TEXT NOT NULL,
    arrive_date TEXT NOT NULL
);
CREATE TABLE port_calls (
    id INTEGER PRIMARY KEY,
    voyage_id INTEGER NOT NULL REFERENCES voyages(id),
    port TEXT NOT NULL,
    arrive_ts TEXT NOT NULL,
    depart_ts TEXT              -- NULL = call still in progress
);
CREATE TABLE cargo (
    id INTEGER PRIMARY KEY,
    voyage_id INTEGER NOT NULL REFERENCES voyages(id),
    bill_of_lading TEXT NOT NULL,
    weight_tons INTEGER NOT NULL,
    commodity TEXT NOT NULL
);
CREATE TABLE params (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
"""

PORTS = ["Rotterdam", "Singapore", "Houston", "Santos",
         "Durban", "Yokohama", "Hamburg", "Antwerp"]
FLAGS = ["PA", "LR", "SG", "MT", "KY"]
KLASSES = ["bulker", "tanker", "container", "general"]
COMMODITIES = ["grain", "crude", "lng", "ore", "containers", "machinery"]
WORDS = ["Aurora", "Borealis", "Cormorant", "Diligent", "Eland", "Frigate",
         "Gannet", "Halcyon", "Isolde", "Juniper", "Kestrel", "Lancer",
         "Meridian", "Naiad", "Osprey", "Petrel", "Quill", "Rhea",
         "Sable", "Tern", "Umber", "Vela", "Wren", "Yarrow"]
ROMAN = ["I", "II", "III", "IV", "V"]


def main(out, seed):
    rng = random.Random(seed)
    con = sqlite3.connect(out)
    cur = con.cursor()
    cur.executescript(SCHEMA)

    names = rng.sample(WORDS, 18)
    vessels = []
    for i, w in enumerate(names, 1):
        name = "MV %s %s" % (w, rng.choice(ROMAN))
        vessels.append((i, name, rng.choice(FLAGS), rng.choice(KLASSES)))
    cur.executemany("INSERT INTO vessels VALUES (?,?,?,?)", vessels)

    nv = 0
    voyage_rows = []
    for _ in range(60):
        nv += 1
        vid = rng.randrange(1, len(vessels) + 1)
        o, d = rng.sample(PORTS, 2)
        dep = datetime(2031, 1, 1) + timedelta(days=rng.randrange(0, 320))
        arr = dep + timedelta(days=rng.randrange(2, 10))
        voyage_rows.append((nv, vid, o, d, dep.date().isoformat(),
                            arr.date().isoformat()))
    cur.executemany("INSERT INTO voyages VALUES (?,?,?,?,?,?)", voyage_rows)

    nc = 0
    call_rows = []
    cargo_rows = []
    bol_reuse = []
    for (vid, _, _, _, dep_date, arr_date) in voyage_rows:
        stops = rng.sample(PORTS, rng.randrange(1, 4))
        if stops[-1] != voyage_rows[nv - 1][3]:
            stops[-1] = voyage_rows[nv - 1][3]
        clock = datetime.fromisoformat(arr_date + "T00:00:00")
        for port in stops:
            nc += 1
            dwell_h = rng.randrange(6, 61)
            arrive_ts = clock.strftime("%Y-%m-%dT%H:%M:%S")
            # ~15% of calls are still in progress (NULL departure)
            depart_ts = None if rng.random() < 0.15 else (
                clock + timedelta(hours=dwell_h)).strftime("%Y-%m-%dT%H:%M:%S")
            call_rows.append((nc, vid, port, arrive_ts, depart_ts))
            clock += timedelta(hours=dwell_h + rng.randrange(4, 24))
        for _ in range(rng.randrange(2, 7)):
            bol = "BL-2031-%04d" % rng.randrange(1, 400)
            if bol_reuse and rng.random() < 0.15:
                bol = rng.choice(bol_reuse)   # deliberate duplicate paperwork
            bol_reuse.append(bol)
            cargo_rows.append((len(cargo_rows) + 1, vid, bol,
                               rng.randrange(400, 26000),
                               rng.choice(COMMODITIES)))
    cur.executemany("INSERT INTO port_calls VALUES (?,?,?,?,?)", call_rows)
    cur.executemany("INSERT INTO cargo VALUES (?,?,?,?,?)", cargo_rows)

    cur.executemany("INSERT INTO params VALUES (?,?)",
                    [("window_from", "2031-02-01"),
                     ("window_to", "2031-04-30")])
    con.commit()
    con.close()
    print("generated %s: %d vessels, %d voyages, %d calls, %d cargo rows"
          % (out, len(vessels), len(voyage_rows), len(call_rows), len(cargo_rows)))


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]))
