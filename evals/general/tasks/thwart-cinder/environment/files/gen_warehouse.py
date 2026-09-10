#!/usr/bin/env python3
"""Build the Meridian Freight warehouse cluster and load the fact tables.

Runs once at image build time (as root) and then is removed from the image.
Produces a *stopped* PostgreSQL 16 cluster at /srv/pgdata containing database
`analytics` with two index-free fact tables:

    events    2,000,000 rows   (service events; columns tenant/region/kind/
                                occurred_at/amount/note)
    journeys  1,200,000 rows   (trip legs;    same shape, distance_km instead
                                of amount)

All randomness is seeded, so every build of the image yields byte-identical
rows and fingerprints. The cluster is ANALYZEd and shut down cleanly, and the
fingerprints the publisher will need are printed and written to
/build/manifest.txt (build dir only; never shipped into the image).

Environment facts the trial depends on (documented in instruction.md):
    connection:  psql -h 127.0.0.1 -p 5433 -U postgres -d analytics
    cluster dir: /srv/pgdata  (owner postgres, stopped, ready to start)
"""
import csv
import os
import random
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta

RND = random.Random(20250917)

DATA = "/srv/pgdata"
DB = "analytics"
PORT = "5433"
PGBIN = "/usr/lib/postgresql/16/bin"
if not os.path.isdir(PGBIN):
    import glob
    hits = sorted(glob.glob("/usr/lib/postgresql/*/bin"))
    if not hits:
        sys.exit("postgres server binaries not found")
    PGBIN = hits[-1]

REGIONS = ("north", "south", "east", "west", "central")
EVENT_KINDS = ("inspection", "triage", "repair", "upgrade", "audit")
JOURNEY_KINDS = ("pickup", "linehaul", "delivery", "return")
LOREM = (
    "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima "
    "mike november oscar papa quebec romeo sierra tango uniform victor whiskey "
    "xray yankee zulu amber blue cyan den ebony falcon garnet hazel indigo "
    "jade khaki lilac mauve navy onyx pearl quartz rose slate teal violet "
    "wheat xeno yew zinc".split()
)
START = datetime(2024, 1, 1, 0, 0, 0)
TOTAL_SECONDS = int((datetime(2026, 3, 1, 0, 0, 0) - START).total_seconds())


def run(cmd, check=True, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if check and r.returncode != 0:
        sys.stderr.write("$ %s\n%s%s" % (" ".join(cmd), r.stdout, r.stderr))
        sys.exit(1)
    return r


def gen_rows(n_rows, kinds, metric, out_path):
    """Stream n_rows CSV lines. Column order:
    tenant_id,region,kind,occurred_at,amount-or-km,note
    """
    with open(out_path, "w", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        for i in range(n_rows):
            ts = START + timedelta(seconds=RND.randint(0, TOTAL_SECONDS - 1))
            region = REGIONS[RND.randrange(len(REGIONS))]
            kind = kinds[RND.randrange(len(kinds))]
            base = RND.randrange(len(LOREM))
            note = " ".join(LOREM[(base + j) % len(LOREM)] for j in range(8))
            w.writerow([
                RND.randrange(1, 201),     # tenant_id
                region,
                kind,
                ts.strftime("%Y-%m-%d %H:%M:%S"),
                "%.2f" % (RND.randrange(1000, 500000) / 100.0) if metric == "amount"
                else "%.2f" % (RND.randrange(500, 150000) / 100.0),
                note,
            ])


def main():
    os.makedirs(DATA, exist_ok=True)
    run(["chown", "-R", "postgres:postgres", DATA])
    if not os.path.exists(os.path.join(DATA, "PG_VERSION")):
        run(["su", "postgres", "-c",
             "%s/initdb -D %s -U postgres --auth=trust --no-locale -E UTF8"
             % (PGBIN, DATA)])
    conf = os.path.join(DATA, "postgresql.conf")
    with open(conf, "a") as fh:
        fh.write(
            "\n# --- thwart-cinder build settings ---\n"
            "port = %s\n"
            "listen_addresses = '127.0.0.1'\n"
            "unix_socket_directories = '/tmp'\n"
            "max_parallel_workers_per_gather = 0\n"
            "max_parallel_workers = 0\n"
            "checkpoint_completion_target = 0.9\n" % PORT)

    run(["su", "postgres", "-c", "%s/pg_ctl -D %s -l /tmp/pg_build.log start"
         % (PGBIN, DATA)])
    try:
        run([PGBIN + "/psql", "-h", "127.0.0.1", "-p", PORT, "-U", "postgres",
             "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-q", "-c",
             "CREATE DATABASE %s" % DB])
        schema = open("/build/warehouse/schema.sql").read()
        run([PGBIN + "/psql", "-h", "127.0.0.1", "-p", PORT, "-U", "postgres",
             "-d", DB, "-v", "ON_ERROR_STOP=1", "-q", "-c", schema])

        with tempfile.TemporaryDirectory(prefix="mf-") as td:
            os.chmod(td, 0o755)  # the postgres server user must read the CSVs
            ev = os.path.join(td, "events.csv")
            jy = os.path.join(td, "journeys.csv")
            gen_rows(2_000_000, EVENT_KINDS, "amount", ev)
            gen_rows(1_200_000, JOURNEY_KINDS, "km", jy)
            for table, path in (("events", ev), ("journeys", jy)):
                run([PGBIN + "/psql", "-h", "127.0.0.1", "-p", PORT,
                     "-U", "postgres", "-d", DB, "-q", "-c",
                     "COPY %s (tenant_id,region,kind,occurred_at,%s,note) "
                     "FROM '%s' WITH (FORMAT csv)"
                     % (table, "amount" if table == "events" else "distance_km",
                        path)])

        run([PGBIN + "/psql", "-h", "127.0.0.1", "-p", PORT, "-U", "postgres",
             "-d", DB, "-q", "-c", "VACUUM ANALYZE events"])
        run([PGBIN + "/psql", "-h", "127.0.0.1", "-p", PORT, "-U", "postgres",
             "-d", DB, "-q", "-c", "VACUUM ANALYZE journeys"])

        fp = ("SELECT count(*)::text||'|'||min(id)::text||'|'||max(id)::text||'|'||"
              "sum(amount)::text||'|'||"
              "md5(string_agg(id::text, ',' ORDER BY id))||'|'||"
              "md5(string_agg(region||'|'||kind||'|'||amount::text||'|'||"
              "to_char(occurred_at,'YYYY-MM-DD HH24:MI:SS'), ';' ORDER BY id)) "
              "FROM events")
        fpj = fp.replace("amount", "distance_km").replace("FROM events",
                                                          "FROM journeys")
        out = run([PGBIN + "/psql", "-h", "127.0.0.1", "-p", PORT, "-U",
                   "postgres", "-d", DB, "-A", "-t", "-q", "-c", fp])
        outj = run([PGBIN + "/psql", "-h", "127.0.0.1", "-p", PORT, "-U",
                    "postgres", "-d", DB, "-A", "-t", "-q", "-c", fpj])
        evfp = out.stdout.strip()
        jyfp = outj.stdout.strip()
        with open("/build/manifest.txt", "w") as fh:
            fh.write("EVENTS_FP=" + evfp + "\nJOURNEYS_FP=" + jyfp + "\n")
        print("manifest written: EVENTS_FP=%s" % evfp)
        print("manifest written: JOURNEYS_FP=%s" % jyfp)
    finally:
        run(["su", "postgres", "-c",
             "%s/pg_ctl -D %s -m fast stop" % (PGBIN, DATA)], check=False)
    print("warehouse build complete: events=2,000,000 journeys=1,200,000")


if __name__ == "__main__":
    main()