#!/usr/bin/env bash
# Oracle for granary-ledge: derives the connection from the compose-style
# stack file (as the task demands), opens a live connection, and writes the
# two deliverables: the reusable /app/inspect.py program and /app/report.json
# produced by running it on the provided stack. Never reads /tests.
set -euo pipefail

/opt/groundctl/dbctl.sh up

# ---- deliverable 1: the reusable inspection program ------------------------
cat > /app/inspect.py <<'PY'
#!/usr/bin/env python3
"""granary-ledge low-stock reporter.

Usage: python3 /app/inspect.py <stack_file> <output_json>

Derives the Postgres connection (service, database, user, password, host
port) from the given compose-style stack file, connects to the live
instance, and writes the low-stock report as JSON.
"""
import json
import sys

import psycopg2
import yaml


def find_postgres_service(doc):
    services = doc.get("services") or {}
    for name, svc in services.items():
        svc = svc or {}
        if "postgres" in str(svc.get("image", "")):
            return name, svc
    raise SystemExit("no postgres service in stack file")


def env_as_dict(env):
    if env is None:
        return {}
    if isinstance(env, list):
        out = {}
        for entry in env:
            key, _, value = str(entry).partition("=")
            out[key.strip()] = value.strip()
        return out
    return dict(env)


def host_port(svc):
    ports = svc.get("ports") or []
    if not ports:
        raise SystemExit("postgres service publishes no ports")
    first = str(ports[0]).split(":")
    return int(first[0])


def main():
    stack_path, out_path = sys.argv[1], sys.argv[2]
    with open(stack_path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)

    name, svc = find_postgres_service(doc)
    env = env_as_dict(svc.get("environment"))
    dbname = env["POSTGRES_DB"]
    user = env["POSTGRES_USER"]
    password = env["POSTGRES_PASSWORD"]
    port = host_port(svc)

    conn = psycopg2.connect(host="127.0.0.1", port=port, dbname=dbname,
                            user=user, password=password, connect_timeout=10)
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT sku, name, stock, reorder_point, price "
            "FROM items ORDER BY sku ASC"
        )
        low = []
        units = 0
        value = 0.0
        for sku, iname, stock, reorder, price in cur.fetchall():
            shortfall = int(reorder) - int(stock)
            if shortfall > 0:
                low.append({"sku": sku, "name": iname,
                            "stock": int(stock), "reorder_point": int(reorder)})
                units += shortfall
                value += shortfall * float(price)
        report = {
            "service": name,
            "database": dbname,
            "low_stock": low,
            "restock_units": units,
            "restock_value": round(value, 2),
        }
    finally:
        conn.close()

    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)


if __name__ == "__main__":
    main()
PY
chmod 0755 /app/inspect.py

# ---- deliverable 2: run it on the provided stack ---------------------------
python3 /app/inspect.py /app/deploy/stack.yml /app/report.json

echo "granary-ledge oracle done"
ls -l /app/inspect.py /app/report.json
