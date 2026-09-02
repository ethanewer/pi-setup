#!/usr/bin/env python3
"""
larch-fathom solver.

A single reusable program that stands up a live local Postgres data tier, fully
driven by command-line arguments so fresh hidden fixtures run unchanged:

    python3 solve.py <DATA_CSV> <PROTO> <OUTDIR> <ANSWER_JSON>

1. Brings up the Postgres service (no systemd) if it is not already listening,
   provisions the app role + database + grants, and writes /app/database.env
   exposing DATABASE_URL.
2. Creates the `customers` table to the prescribed schema and loads the rows of
   DATA_CSV into a raw staging table (evidence dumped to /app/load.sql).
3. Cleans the data entirely in SQL: lowercase+trim on email, digit-only on
   phone, drop duplicates (keep earliest by email+phone) and delete rows
   missing both contact fields; /app/clean.sql records the statements run.
4. Creates a `users` table, crafts and EXERCISES a SQL-injection payload that
   must authenticate as the 'admin' role, and records the result.
5. Generates python bindings (x_pb2.py + x_pb2_grpc.py) from PROTO into OUTDIR.

Writes ENV_JSON (JSON description of what was done) — the second deliverable.
Drive is purely by the four CLI arguments; nothing else is hard-coded.
"""

import csv
import glob
import json
import os
import subprocess
import sys
import time

WORK = "/app"
APP_ROLE = "hopper"
APP_PASS = "hopp3rXp12"
APP_DB = "hopper"
URL = "postgresql://%s:%s@127.0.0.1:5432/%s" % (APP_ROLE, APP_PASS, APP_DB)


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)


def su_psql(sql, db=None):
    c = ["su", "postgres", "-c", "psql -v ON_ERROR_STOP=1%s" % (" -d %s" % db if db else "")]
    return subprocess.run(c, input=sql, capture_output=True, text=True)


def psql(url, sql, ta=False):
    c = ["psql", url, "-v", "ON_ERROR_STOP=1"]
    if ta:
        c.append("-tA")
    return subprocess.run(c, input=sql, capture_output=True, text=True)


def fail(msg):
    sys.stderr.write("solver: %s\n" % msg)
    sys.exit(1)


def _esc(s):
    return (s or "").replace("\\", "\\\\").replace("'", "''")


def ensure_server():
    for _ in range(120):
        if sh("pg_isready -q -h 127.0.0.1 -p 5432").returncode == 0:
            break
        if _ == 0:
            vdirs = sorted(glob.glob("/usr/lib/postgresql/[0-9]*"))
            version = vdirs[-1].rsplit("/", 1)[-1] if vdirs else None
            # cluster exists if pg_lsclusters lists a main entry
            have = "main" in sh("pg_lsclusters").stdout
            if not have and version:
                sh("pg_createcluster %s main" % version)
            if version:
                sh("pg_ctlcluster %s main start" % version)
        time.sleep(0.5)
    if sh("pg_isready -q -h 127.0.0.1 -p 5432").returncode != 0:
        fail("postgres did not come up")


def provision():
    r = su_psql("SELECT 1 FROM pg_roles WHERE rolname='%s'" % APP_ROLE)
    if "1" not in r.stdout:
        su_psql("CREATE ROLE %s LOGIN PASSWORD '%s';" % (APP_ROLE, APP_PASS))
    r = su_psql("SELECT 1 FROM pg_database WHERE datname='%s'" % APP_DB)
    if "1" not in r.stdout:
        su_psql("CREATE DATABASE %s OWNER %s;" % (APP_DB, APP_ROLE))
    su_psql("GRANT ALL PRIVILEGES ON DATABASE %s TO %s;" % (APP_DB, APP_ROLE))
    su_psql("GRANT ALL ON SCHEMA public TO %s;" % APP_ROLE, APP_DB)
    su_psql("ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO %s;" % APP_ROLE, APP_DB)


def schema_sql():
    return (
        "DROP TABLE IF EXISTS customers CASCADE;\n"
        "DROP TABLE IF EXISTS customers_raw CASCADE;\n"
        "CREATE TABLE customers (\n"
        "    id SERIAL PRIMARY KEY,\n"
        "    full_name TEXT NOT NULL,\n"
        "    email TEXT,\n"
        "    phone TEXT,\n"
        "    region TEXT\n"
        ");\n"
        "CREATE TABLE customers_raw (LIKE customers INCLUDING ALL);\n"
    )


def read_rows(data_csv):
    rows = []
    with open(data_csv, newline="") as fh:
        reader = csv.DictReader(fh, fieldnames=["full_name", "email", "phone", "region"])
        for row in reader:
            vals = [row.get("full_name"), row.get("email"), row.get("phone"), row.get("region")]
            if vals[0] is None and vals[1:] == [None, None, None]:
                continue  # fully blank line
            if (vals[0] or "").strip().lower() == "full_name":
                continue  # documented header row
            rows.append(vals)
    return rows


CLEAN_SQL = (
    "BEGIN;\n"
    "-- lowercase + trim the email address column\n"
    "UPDATE customers SET email = btrim(lower(coalesce(email,'')))\n"
    "   WHERE coalesce(email,'') <> '';\n"
    "-- extract digits only into the phone column\n"
    "UPDATE customers SET phone = regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g');\n"
    "-- drop duplicate (email, phone) rows, keeping the earliest\n"
    "DELETE FROM customers c WHERE EXISTS (\n"
    "  SELECT 1 FROM customers d\n"
    "   WHERE coalesce(d.email,'') = coalesce(c.email,'')\n"
    "     AND coalesce(d.phone,'') = coalesce(c.phone,'')\n"
    "     AND d.id < c.id );\n"
    "-- delete rows carrying neither signal\n"
    "DELETE FROM customers WHERE coalesce(email,'')='' AND coalesce(phone,'')='';\n"
    "COMMIT;\n"
)

USERS_SQL = (
    "DROP TABLE IF EXISTS users;\n"
    "CREATE TABLE users (\n"
    "  id SERIAL PRIMARY KEY,\n"
    "  username TEXT NOT NULL UNIQUE,\n"
    "  password TEXT,\n"
    "  role TEXT\n"
    ");\n"
    "INSERT INTO users (username, password, role) VALUES\n"
    "  ('admin',  'K8l-#9qZ1w0', 'administrator'),\n"
    "  ('ana', 'sV3n-7tYx9', 'analyst');\n"
)


def main():
    if len(sys.argv) != 5:
        fail("usage: solve.py <DATA_CSV> <PROTO> <OUTDIR> <ANSWER_JSON>")
    data_csv, proto, outdir, answer_json = sys.argv[1:5]

    if not os.path.isfile(data_csv):
        fail("data csv not found: " + data_csv)
    if not os.path.isfile(proto):
        fail("proto not found: " + proto)

    ensure_server()
    provision()

    # persist connection string
    with open(os.path.join(WORK, "database.env"), "w") as fh:
        fh.write("export DATABASE_URL=\"%s\"\n" % URL)

    r = psql(URL, "SELECT 1;")
    if r.returncode != 0:
        fail("app connection failed: " + r.stderr)

    # schema
    r = psql(URL, schema_sql())
    if r.returncode != 0:
        fail("schema failed: " + r.stderr)

    # load
    rows = read_rows(data_csv)
    stmt_lines = []
    for full, em, ph, region in rows:
        full_e = _esc(full)
        region_e = _esc(region)
        em_s = "NULL" if not em else "'%s'" % _esc(em)
        ph_s = "NULL" if not ph else "'%s'" % _esc(ph)
        stmt_lines.append("('%s', %s, %s, '%s')" % (full_e, em_s, ph_s, region_e))
    if not stmt_lines:
        # still create empty tables (already done) and continue
        pass
    else:
        load_sql = (
            "INSERT INTO customers_raw (full_name, email, phone, region) VALUES\n%s;\n"
            "INSERT INTO customers (full_name, email, phone, region)\n"
            "  SELECT full_name, email, phone, region FROM customers_raw;\n" % ",\n".join(stmt_lines)
        )
        with open(os.path.join(WORK, "load.sql"), "w") as fh:
            fh.write(load_sql)
        r = psql(URL, load_sql)
        if r.returncode != 0:
            fail("load failed: " + r.stderr)
    total = len(stmt_lines)

    # clean
    with open(os.path.join(WORK, "clean.sql"), "w") as fh:
        fh.write(CLEAN_SQL)
    r = psql(URL, CLEAN_SQL)
    if r.returncode != 0:
        fail("clean failed: " + r.stderr)
    cleaned = int(psql(URL, "SELECT count(*) FROM customers;", ta=True).stdout.strip() or "0")

    # users + auth bypass
    r = psql(URL, USERS_SQL, True)
    if r.returncode != 0:
        fail("users failed: " + r.stderr)
    username = "admin' OR '1'='1' --"
    password = "noop"
    forged = ("SELECT role FROM users WHERE username='%s' AND password='%s';" % (username, password))
    rr = psql(URL, forged, ta=True)
    role = rr.stdout.strip().splitlines()[0] if rr.stdout.strip() else ""

    # bindings
    os.makedirs(outdir, exist_ok=True)
    base = os.path.splitext(os.path.basename(proto))[0]
    modnames = ["%s_pb2.py" % base, "%s_pb2_grpc.py" % base]
    inc = os.path.dirname(os.path.abspath(proto)) or "."
    rr2 = sh("python3 -m grpc_tools.protoc -I%s --python_out=%s --grpc_python_out=%s %s"
             % (inc, outdir, outdir, os.path.basename(proto)))
    if rr2.returncode != 0:
        fail("proto generation failed: " + rr2.stderr.strip())

    importable = all(os.path.isfile(os.path.join(outdir, m)) for m in modnames)
    ans = {
        "schema": ["full_name", "email", "phone", "region"],
        "target_role": "administrator",
        "forged_role": role,
        "bypass_worked": role == "administrator",
        "username": username,
        "password": password,
        "forged_sql": forged,
        "total": total,
        "cleaned": cleaned,
        "modules": modnames,
        "importable": importable,
        "database_url": URL,
    }
    with open(answer_json, "w") as fh:
        json.dump(ans, fh, indent=2)

    if role != "administrator":
        fail("auth bypass did not yield administrator")
    if not importable:
        fail("bindings not generated")
    print("ok cleaned=%d role=%s modules=%s" % (cleaned, role, modnames))


if __name__ == "__main__":
    main()