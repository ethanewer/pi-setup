#!/bin/bash
#
# moor-atlas oracle. Does the real work: writes the audit program, then RUNS
# it on the visible stack fixture to produce /app/audit.json. Never reads
# /tests.
set -euo pipefail

/opt/moorctl/dbctl.sh up

cat > /app/audit.py <<'PY'
#!/usr/bin/env python3
"""Moor Atlas beacon audit: derive Postgres connection settings from a
compose-style stack file, open a live connection, and census the beacons
table."""
import json
import sys

import psycopg2
import yaml

HOST = "127.0.0.1"
FAIL_EXIT = 2


def die(msg):
    sys.stderr.write("audit.py: %s\n" % msg)
    sys.exit(FAIL_EXIT)


def parse_stack(path):
    try:
        with open(path, encoding="utf-8") as fh:
            doc = yaml.safe_load(fh)
    except Exception as exc:
        die("cannot read stack file %s (%s)" % (path, exc))
    if not isinstance(doc, dict):
        die("stack file is not a mapping")
    services = doc.get("services") or {}
    if not isinstance(services, dict):
        die("stack file has no services mapping")
    for name, svc in services.items():
        svc = svc or {}
        image = str(svc.get("image", ""))
        if "postgres" not in image.lower():
            continue
        env = svc.get("environment") or {}
        if isinstance(env, list):
            env = dict(str(e).split("=", 1) for e in env if "=" in str(e))
        dbname = env.get("POSTGRES_DB")
        user = env.get("POSTGRES_USER")
        password = env.get("POSTGRES_PASSWORD")
        hostport = None
        ports = svc.get("ports") or []
        if isinstance(ports, dict):
            for v in ports.values():
                hostport = int(str(v).split(":", 1)[0])
                break
        else:
            for p in ports:
                s = str(p)
                if ":" in s:
                    hostport = int(s.split(":", 1)[0])
                    break
        if not (dbname and user and password and hostport):
            die("incomplete connection settings for service %r" % name)
        return {"database": str(dbname), "user": str(user),
                "password": str(password), "port": int(hostport)}
    die("no postgres service in stack file")


def main():
    if len(sys.argv) != 3:
        die("usage: audit.py <stack_file> <output_json>")
    stack_path, out_path = sys.argv[1], sys.argv[2]
    s = parse_stack(stack_path)

    try:
        conn = psycopg2.connect(host=HOST, port=s["port"], dbname=s["database"],
                                user=s["user"], password=s["password"],
                                connect_timeout=5)
    except Exception as exc:
        die("connection to 127.0.0.1:%d db=%s user=%s failed: %s"
            % (s["port"], s["database"], s["user"], exc))

    try:
        cur = conn.cursor()
        cur.execute("SELECT count(*) FROM beacons")
        total = int(cur.fetchone()[0])
        cur.execute("SELECT count(*) FROM beacons WHERE status = 'active'")
        active = int(cur.fetchone()[0])
        cur.execute("SELECT grid, count(*) FROM beacons WHERE status = 'active' "
                    "GROUP BY grid ORDER BY grid")
        by_grid = {g: int(n) for g, n in cur.fetchall()}
        cur.execute("SELECT code, grid, strength FROM beacons "
                    "ORDER BY strength DESC, beacon_id ASC LIMIT 1")
        row = cur.fetchone()
        strongest = ({"code": row[0], "grid": row[1], "strength": int(row[2])}
                     if row is not None else None)
    except Exception as exc:
        die("query failed: %s" % exc)
    finally:
        conn.close()

    answer = {
        "database": s["database"],
        "user": s["user"],
        "port": s["port"],
        "beacons_total": total,
        "active": active,
        "by_grid": by_grid,
        "strongest": strongest,
    }
    # The output file is created only after everything succeeded.
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(answer, fh, indent=2, sort_keys=False)


if __name__ == "__main__":
    main()
PY
chmod +x /app/audit.py

python3 /app/audit.py /app/deploy/services.yml /app/audit.json

# TEMP DEBUG PROBE (remove before final)
python3 - <<'EOF' > /tmp/probe.txt 2>&1
import subprocess, glob, psycopg2
PGBIN = sorted(glob.glob('/usr/lib/postgresql/*/bin'))[-1]
for port in (5581, 5591):
    out = subprocess.run([PGBIN + '/psql', '-U', 'postgres', '-p', str(port), '-d', 'postgres', '-tA', '-F', '|', '-c',
                          'select pg_postmaster_start_time(), current_setting(\'data_directory\'), current_setting(\'hba_file\'), current_setting(\'port\')'], capture_output=True, text=True)
    print('SOCKET p%d ->' % port, out.stdout.strip(), out.stderr.strip())
for f in ('/var/lib/moordb/postmaster.opts', '/var/lib/moordecoy/postmaster.opts'):
    try:
        print(f, '->', open(f).read().strip())
    except Exception as e:
        print(f, 'ERR', e)
print(subprocess.run(['pgrep', '-a', 'postgres'], capture_output=True, text=True).stdout)
for pw in ('WRONG-Creed-0000', 'Torren-Feil-3319'):
    try:
        c = psycopg2.connect(host='127.0.0.1', port=5581, dbname='moorside', user='surveyor', password=pw, connect_timeout=5)
        cur = c.cursor(); cur.execute('select current_user, current_setting(\'data_directory\')')
        print('TCP CONNECTED with pw=%s ->' % pw[:6], cur.fetchone())
        c.close()
    except Exception as e:
        print('TCP FAILED with pw=%s ->' % pw[:6], str(e)[:200])
EOF
# END TEMP DEBUG PROBE

echo "moor-atlas oracle complete"
ls -l /app/audit.py /app/audit.json
exit 0
